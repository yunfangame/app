part of '../action.dart';

enum HongKongSelectionResult { selected, unavailable, failed, cancelled }

enum ModeSwitchResult { switched, unchanged, failed, cancelled }

class ModeSwitchRecoveryException implements Exception {
  const ModeSwitchRecoveryException(this.cause);

  final Object cause;
}

Profile? _restoredModeProfile({
  required Profile original,
  required Profile committed,
  required Profile current,
  Set<String> preservedSelectionKeys = const {},
}) {
  if (current.id != original.id ||
      current.url != original.url ||
      current.lastUpdateDate != original.lastUpdateDate) {
    return null;
  }
  final restoredSelections = Map<String, String>.from(current.selectedMap);
  final changedKeys = {
    ...original.selectedMap.keys,
    ...committed.selectedMap.keys,
  };
  for (final key in changedKeys) {
    if (preservedSelectionKeys.contains(key)) continue;
    final originalHasKey = original.selectedMap.containsKey(key);
    final committedHasKey = committed.selectedMap.containsKey(key);
    if (originalHasKey == committedHasKey &&
        original.selectedMap[key] == committed.selectedMap[key]) {
      continue;
    }
    if (restoredSelections.containsKey(key) != committedHasKey ||
        restoredSelections[key] != committed.selectedMap[key]) {
      continue;
    }
    if (originalHasKey) {
      restoredSelections[key] = original.selectedMap[key]!;
    } else {
      restoredSelections.remove(key);
    }
  }
  final restoredGroupName =
      committed.currentGroupName != original.currentGroupName &&
          current.currentGroupName == committed.currentGroupName
      ? original.currentGroupName
      : current.currentGroupName;
  final restored = current.copyWith(
    currentGroupName: restoredGroupName,
    selectedMap: restoredSelections,
  );
  return restored == current ? null : restored;
}

@Riverpod(keepAlive: true)
class ProxiesAction extends _$ProxiesAction {
  final _selectionScheduler = SerialTaskScheduler();
  int _hongKongSelectionRevision = 0;
  int _modeSelectionRevision = 0;
  int _manualSelectionRevision = 0;
  final Map<String, ({int revision, String proxyName})>
  _manualSelectionIntents = {};

  @override
  void build() {}

  @protected
  CoreController get proxyController => coreController;

  int get hongKongSelectionRevision => _hongKongSelectionRevision;
  int get manualSelectionRevision => _manualSelectionRevision;

  bool hasManualSelectionAfter(String groupName, int revision) {
    final intent = _manualSelectionIntents[groupName];
    return intent != null && intent.revision > revision;
  }

  Future<T> runSelectionTransaction<T>(Future<T> Function() transaction) {
    return _selectionScheduler.run(transaction);
  }

  void cancelHongKongSelection({bool manual = false}) {
    _hongKongSelectionRevision++;
    if (manual) {
      _manualSelectionRevision++;
      _modeSelectionRevision++;
    }
  }

  void _recordManualSelection(String groupName, String proxyName) {
    cancelHongKongSelection(manual: true);
    _manualSelectionIntents[groupName] = (
      revision: manualSelectionRevision,
      proxyName: proxyName,
    );
  }

  @protected
  Duration get hongKongProbeTimeout => const Duration(seconds: 6);

  @protected
  Duration get hongKongSelectionTimeout => const Duration(seconds: 20);

  Future<HongKongSelectionResult> selectHongKongForMode(
    Mode mode, {
    bool Function()? isCancelled,
  }) async {
    cancelHongKongSelection();
    _modeSelectionRevision++;
    final revision = _hongKongSelectionRevision;
    final profile = ref.read(currentProfileProvider);
    if (profile == null || mode == Mode.direct) {
      return HongKongSelectionResult.unavailable;
    }
    final initialChain = activeChainProxy(ref.read(appSettingProvider));
    if (mode == Mode.global && initialChain != null) {
      commonPrint.event(
        'proxy.hong_kong_selection.failed',
        fields: {
          'mode': mode.name,
          'reason': 'chain_proxy_requires_explicit_selection',
        },
      );
      return HongKongSelectionResult.failed;
    }
    final sessionRevision = globalState.xboardSessionRevision;
    final originalMode = ref.read(patchClashConfigProvider).mode;
    var committingMode = false;
    var ownershipLost = false;
    bool ownsProfile() {
      if (!ref.mounted) return false;
      final activeProfile = ref.read(currentProfileProvider);
      return !ownershipLost &&
          ref.read(currentProfileIdProvider) == profile.id &&
          activeProfile?.url == profile.url &&
          activeProfile?.lastUpdateDate == profile.lastUpdateDate &&
          sessionRevision == globalState.xboardSessionRevision;
    }

    bool current() {
      if (!ownsProfile()) return false;
      final activeProfile = ref.read(currentProfileProvider);
      final activeMode = ref.read(patchClashConfigProvider).mode;
      return activeProfile == profile &&
          activeChainProxy(ref.read(appSettingProvider)) == initialChain &&
          (activeMode == originalMode ||
              committingMode && activeMode == mode) &&
          revision == _hongKongSelectionRevision &&
          isCancelled?.call() != true;
    }

    final profileSubscription = ref.listen(currentProfileProvider, (
      prev,
      next,
    ) {
      if (next?.id != profile.id ||
          next?.url != profile.url ||
          next?.lastUpdateDate != profile.lastUpdateDate) {
        ownershipLost = true;
      }
      if (prev != next) cancelHongKongSelection();
    });
    final modeSubscription = ref.listen(
      patchClashConfigProvider.select((config) => config.mode),
      (prev, next) {
        if (prev != next && !(committingMode && next == mode)) {
          cancelHongKongSelection();
        }
      },
    );
    final runningSubscription = ref.listen(runTimeProvider, (prev, next) {
      if (prev != null && next == null) cancelHongKongSelection();
    });
    final coreSubscription = ref.listen(coreStatusProvider, (prev, next) {
      if (prev != next && next != CoreStatus.connected) {
        ownershipLost = true;
        cancelHongKongSelection();
      }
    });
    final chainSubscription = ref.listen(
      appSettingProvider.select(activeChainProxy),
      (prev, next) {
        if (prev != next) cancelHongKongSelection();
      },
    );
    final timer = Stopwatch()..start();
    final fields = {'mode': mode.name, 'profile_id': profile.id};
    commonPrint.event('proxy.hong_kong_selection.started', fields: fields);
    try {
      final ruleGroup = mode == Mode.rule
          ? ref.read(setupActionProvider.notifier).ruleSelectionGroup
          : null;
      final candidates =
          hongKongCandidates(
                mode: mode,
                groups: ref.read(groupsProvider),
                selectedMap: profile.selectedMap,
                currentGroupName: ruleGroup ?? profile.currentGroupName,
              )
              .where(
                (candidate) =>
                    ruleGroup == null || candidate.groupName == ruleGroup,
              )
              .where(
                (candidate) => !isXboardNodeMarkedOffline(
                  candidate.nodeName,
                  globalState.xboardNodes,
                ),
              )
              .toList();
      for (var offset = 0; offset < candidates.length; offset += 4) {
        if (!current()) return HongKongSelectionResult.cancelled;
        final remaining = hongKongSelectionTimeout - timer.elapsed;
        if (remaining <= Duration.zero) break;
        final timeout = remaining < hongKongProbeTimeout
            ? remaining
            : hongKongProbeTimeout;
        final batch = candidates.skip(offset).take(4).toList();
        final reachable = await Future.wait(
          batch.map((candidate) async {
            try {
              final delay = await proxyController
                  .getDelay(defaultTestUrl, candidate.nodeName)
                  .timeout(timeout);
              if (!current()) return false;
              final valid =
                  delay.name == candidate.nodeName &&
                  delay.url == defaultTestUrl &&
                  (delay.value ?? -1) > 0;
              setDelay(
                Delay(
                  name: candidate.nodeName,
                  url: defaultTestUrl,
                  value: valid ? delay.value : -1,
                ),
              );
              commonPrint.event(
                'proxy.hong_kong_selection.probe',
                fields: {
                  ...fields,
                  'node_ref': diagnosticFingerprint(candidate.nodeName),
                  'reachable': valid,
                  'measured_ms': valid ? delay.value : null,
                },
              );
              return valid;
            } catch (error) {
              if (current()) {
                setDelay(
                  Delay(
                    name: candidate.nodeName,
                    url: defaultTestUrl,
                    value: -1,
                  ),
                );
                commonPrint.event(
                  'proxy.hong_kong_selection.probe_failed',
                  fields: {
                    ...fields,
                    'node_ref': diagnosticFingerprint(candidate.nodeName),
                    'error_type': error.runtimeType.toString(),
                  },
                );
              }
              return false;
            }
          }),
        );
        if (!current()) return HongKongSelectionResult.cancelled;
        final index = reachable.indexWhere((value) => value);
        if (index == -1) continue;
        final candidate = batch[index];
        return await _selectionScheduler.run(() async {
          if (!current()) return HongKongSelectionResult.cancelled;
          if (mode == Mode.rule &&
              ref.read(setupActionProvider.notifier).ruleSelectionGroup !=
                  ruleGroup) {
            return HongKongSelectionResult.cancelled;
          }
          final groups = ref.read(groupsProvider);
          final valid =
              hongKongCandidates(
                mode: mode,
                groups: groups,
                selectedMap: profile.selectedMap,
                currentGroupName: ruleGroup ?? profile.currentGroupName,
              ).any(
                (value) =>
                    value.nodeName == candidate.nodeName &&
                    value.groupName == candidate.groupName &&
                    value.selections.length == candidate.selections.length &&
                    value.selections.entries.every(
                      (entry) => candidate.selections[entry.key] == entry.value,
                    ),
              );
          if (!valid) return HongKongSelectionResult.cancelled;
          final applied = <MapEntry<String, String>>[];
          var succeeded = false;
          try {
            for (final entry
                in candidate.selections.entries.toList().reversed) {
              if (!current()) return HongKongSelectionResult.cancelled;
              final previous = groups
                  .getGroup(entry.key)
                  ?.getCurrentSelectedName(
                    profile.selectedMap[entry.key] ?? '',
                  );
              if (previous?.isNotEmpty == true) {
                applied.add(MapEntry(entry.key, previous!));
              }
              final message = await proxyController.changeProxy(
                ChangeProxyParams(groupName: entry.key, proxyName: entry.value),
              );
              if (message.isNotEmpty) {
                throw StateError('proxy_selection_rejected');
              }
            }
            if (!current()) return HongKongSelectionResult.cancelled;
            committingMode = true;
            final changed = await ref
                .read(setupActionProvider.notifier)
                .applySelectedProxyMode(
                  mode,
                  isCancelled: () => !current(),
                  canRestore: ownsProfile,
                );
            if (!changed || !current()) {
              return HongKongSelectionResult.cancelled;
            }
            final selectionFields = <String, Object>{
              ...fields,
              'node_ref': diagnosticFingerprint(candidate.nodeName),
              'group_ref': diagnosticFingerprint(candidate.groupName),
              'automatic': true,
            };
            ref
                .read(profilesProvider.notifier)
                .put(
                  profile.copyWith(
                    currentGroupName: candidate.groupName,
                    selectedMap: {
                      ...profile.selectedMap,
                      ...candidate.selections,
                    },
                  ),
                );
            succeeded = true;
            final connectionRefreshSucceeded =
                await _resetConnectionsAfterAutomaticSelection(selectionFields);
            commonPrint.event(
              'proxy.hong_kong_selection.succeeded',
              fields: {
                ...selectionFields,
                'connection_refresh_succeeded': connectionRefreshSucceeded,
              },
            );
            ref.read(checkIpNumProvider.notifier).add();
            updateGroupsDebounce();
            return HongKongSelectionResult.selected;
          } finally {
            if (!succeeded) {
              for (final entry in applied.reversed) {
                if (!ownsProfile()) break;
                if (ref.read(currentProfileProvider)?.selectedMap[entry.key] !=
                    profile.selectedMap[entry.key]) {
                  continue;
                }
                try {
                  final message = await proxyController.changeProxy(
                    ChangeProxyParams(
                      groupName: entry.key,
                      proxyName: entry.value,
                    ),
                  );
                  if (message.isNotEmpty) {
                    throw StateError('selection_restore_rejected');
                  }
                } catch (restoreError) {
                  commonPrint.event(
                    'proxy.hong_kong_selection.restore_failed',
                    fields: {
                      ...fields,
                      'error_type': restoreError.runtimeType.toString(),
                    },
                  );
                }
              }
            }
          }
        });
      }
      commonPrint.event(
        'proxy.hong_kong_selection.unavailable',
        fields: fields,
      );
      return HongKongSelectionResult.unavailable;
    } catch (error) {
      commonPrint.event(
        'proxy.hong_kong_selection.failed',
        fields: {...fields, 'error_type': error.runtimeType.toString()},
      );
      return current()
          ? HongKongSelectionResult.failed
          : HongKongSelectionResult.cancelled;
    } finally {
      profileSubscription.close();
      modeSubscription.close();
      runningSubscription.close();
      coreSubscription.close();
      chainSubscription.close();
    }
  }

  Future<ModeSwitchResult> switchModePreservingNode(
    Mode targetMode, {
    required String? ruleGroupName,
    bool Function()? isCancelled,
  }) async {
    cancelHongKongSelection();
    final revision = ++_modeSelectionRevision;
    final originalMode = ref.read(patchClashConfigProvider).mode;
    if (originalMode == targetMode) return ModeSwitchResult.unchanged;
    if (targetMode == Mode.direct) return ModeSwitchResult.failed;
    final profile = ref.read(currentProfileProvider);
    final profileId = ref.read(currentProfileIdProvider);
    final sessionRevision = globalState.xboardSessionRevision;
    final initialManualSelectionRevision = manualSelectionRevision;
    final initialChain = activeChainProxy(ref.read(appSettingProvider));
    if (initialChain != null) {
      commonPrint.event(
        'proxy.mode_switch.failed',
        fields: {
          'from_mode': originalMode.name,
          'to_mode': targetMode.name,
          'reason': 'chain_proxy_requires_full_rebuild',
        },
      );
      return ModeSwitchResult.failed;
    }
    final sourceGroupName = switch ((originalMode, targetMode)) {
      (Mode.rule, Mode.global) => ruleGroupName,
      (Mode.global, Mode.rule) => GroupName.GLOBAL.name,
      _ => null,
    };
    final targetGroupName = switch (targetMode) {
      Mode.global => GroupName.GLOBAL.name,
      Mode.rule => ruleGroupName,
      Mode.direct => null,
    };
    var committingMode = false;
    Profile? committedProfile;
    Profile? acceptedProfileUpdate;
    var ownershipLost = false;

    bool ownsProfile() {
      if (!ref.mounted || ownershipLost) return false;
      final activeProfile = ref.read(currentProfileProvider);
      return ref.read(currentProfileIdProvider) == profileId &&
          activeProfile?.id == profile?.id &&
          activeProfile?.url == profile?.url &&
          activeProfile?.lastUpdateDate == profile?.lastUpdateDate &&
          sessionRevision == globalState.xboardSessionRevision;
    }

    bool current() {
      if (!ownsProfile() || revision != _modeSelectionRevision) return false;
      if (ref.read(currentProfileProvider) != (committedProfile ?? profile)) {
        return false;
      }
      if (ref.read(setupActionProvider.notifier).ruleSelectionGroup !=
          ruleGroupName) {
        return false;
      }
      if (activeChainProxy(ref.read(appSettingProvider)) != initialChain) {
        return false;
      }
      final mode = ref.read(patchClashConfigProvider).mode;
      return (mode == originalMode || committingMode && mode == targetMode) &&
          isCancelled?.call() != true;
    }

    final profileSubscription = ref.listen(currentProfileProvider, (
      previous,
      next,
    ) {
      if (previous != next) {
        if (next == acceptedProfileUpdate) {
          acceptedProfileUpdate = null;
        } else {
          _modeSelectionRevision++;
        }
      }
      if (next?.id != profile?.id ||
          next?.url != profile?.url ||
          next?.lastUpdateDate != profile?.lastUpdateDate) {
        ownershipLost = true;
      }
    });
    final modeSubscription = ref.listen(
      patchClashConfigProvider.select((config) => config.mode),
      (previous, next) {
        if (previous != next && !(committingMode && next == targetMode)) {
          _modeSelectionRevision++;
        }
      },
    );
    final runningSubscription = ref.listen(runTimeProvider, (previous, next) {
      if (previous != null && next == null) _modeSelectionRevision++;
    });
    final coreSubscription = ref.listen(coreStatusProvider, (previous, next) {
      if (previous != next && next != CoreStatus.connected) {
        ownershipLost = true;
        _modeSelectionRevision++;
      }
    });
    final chainSubscription = ref.listen(
      appSettingProvider.select(activeChainProxy),
      (previous, next) {
        if (previous != next) _modeSelectionRevision++;
      },
    );
    final fields = <String, Object>{
      'from_mode': originalMode.name,
      'to_mode': targetMode.name,
      if (profile != null) 'profile_id': profile.id,
    };
    commonPrint.event('proxy.mode_switch.started', fields: fields);
    try {
      return await _selectionScheduler.run(() {
        final setup = ref.read(setupActionProvider.notifier);
        return setup.runModeSwitchTransaction(() async {
          if (!current()) return ModeSwitchResult.cancelled;
          final activeProfile = ref.read(currentProfileProvider);
          final selectedMap = activeProfile?.selectedMap ?? const {};
          final coreActive =
              ref.read(coreStatusProvider) == CoreStatus.connected &&
              ref.read(runTimeProvider) != null;
          final groups = coreActive
              ? await loadModeSwitchGroups()
              : ref.read(groupsProvider);
          if (!current()) return ModeSwitchResult.cancelled;
          final plan = sourceGroupName == null || targetGroupName == null
              ? null
              : planModeNodeSelection(
                  sourceGroupName: sourceGroupName,
                  targetGroupName: targetGroupName,
                  groups: groups,
                  selectedMap: selectedMap,
                );
          final planFields = <String, Object>{
            ...fields,
            'selection_inherited': plan != null,
            if (plan != null) 'node_ref': diagnosticFingerprint(plan.nodeName),
          };
          if (!coreActive) {
            if (!current()) return ModeSwitchResult.cancelled;
            committedProfile = _createModeSelectionProfile(
              profile: activeProfile,
              targetGroupName: targetGroupName,
              selections: plan?.selections ?? const {},
              groups: groups,
            );
            if (committedProfile != null) {
              acceptedProfileUpdate = committedProfile;
              ref.read(profilesProvider.notifier).put(committedProfile!);
            }
            committingMode = true;
            ref
                .read(patchClashConfigProvider.notifier)
                .update((config) => config.copyWith(mode: targetMode));
            debouncer.cancel(FunctionTag.updateConfig);
            commonPrint.event(
              'proxy.mode_switch.succeeded',
              fields: {...planFields, 'core_active': false},
            );
            return ModeSwitchResult.switched;
          }
          final applied = <MapEntry<String, String>>[];
          var succeeded = false;
          try {
            final selections =
                plan?.selections.entries.toList() ??
                const <MapEntry<String, String>>[];
            for (final entry in selections.reversed) {
              if (!current()) return ModeSwitchResult.cancelled;
              final group = groups.getGroup(entry.key);
              if (group == null ||
                  !group.all.any((member) => member.name == entry.value)) {
                throw StateError('proxy_selection_stale');
              }
              final previous = _currentModeSelection(group, selectedMap);
              if (previous == entry.value) continue;
              if (previous.isEmpty) {
                throw StateError('selection_restore_unavailable');
              }
              applied.add(MapEntry(entry.key, previous));
              final message = await proxyController.changeProxy(
                ChangeProxyParams(groupName: entry.key, proxyName: entry.value),
              );
              if (message.isNotEmpty) {
                throw StateError('proxy_selection_rejected');
              }
            }
            if (!current()) return ModeSwitchResult.cancelled;
            committedProfile = _createModeSelectionProfile(
              profile: activeProfile,
              targetGroupName: targetGroupName,
              selections: plan?.selections ?? const {},
              groups: groups,
            );
            if (committedProfile != null) {
              acceptedProfileUpdate = committedProfile;
              ref.read(profilesProvider.notifier).put(committedProfile!);
            }
            if (!current()) return ModeSwitchResult.cancelled;
            committingMode = true;
            final changed = await setup.applySelectedProxyModeWithinTransaction(
              targetMode,
              isCancelled: () => !current(),
              canRestore: ownsProfile,
            );
            if (!changed || !current()) return ModeSwitchResult.cancelled;
            succeeded = true;
            final connectionRefreshSucceeded =
                await applyModeSwitchConnectionPolicy(planFields);
            commonPrint.event(
              'proxy.mode_switch.succeeded',
              fields: {
                ...planFields,
                'core_active': true,
                'connection_refresh_succeeded': connectionRefreshSucceeded,
              },
            );
            ref.read(checkIpNumProvider.notifier).add();
            updateGroupsDebounce();
            return ModeSwitchResult.switched;
          } finally {
            if (!succeeded) {
              Object? restoreFailure;
              if (committedProfile != null &&
                  ownsProfile() &&
                  activeProfile != null) {
                final preservedSelectionKeys = {
                  for (final key in committedProfile!.selectedMap.keys)
                    if (hasManualSelectionAfter(
                      key,
                      initialManualSelectionRevision,
                    ))
                      key,
                };
                final restoredProfile = _restoredModeProfile(
                  original: activeProfile,
                  committed: committedProfile!,
                  current: ref.read(currentProfileProvider)!,
                  preservedSelectionKeys: preservedSelectionKeys,
                );
                committedProfile = null;
                if (restoredProfile != null) {
                  acceptedProfileUpdate = restoredProfile;
                  ref.read(profilesProvider.notifier).put(restoredProfile);
                }
              }
              for (final entry in applied.reversed) {
                if (!ownsProfile()) break;
                if (hasManualSelectionAfter(
                  entry.key,
                  initialManualSelectionRevision,
                )) {
                  continue;
                }
                try {
                  final message = await proxyController.changeProxy(
                    ChangeProxyParams(
                      groupName: entry.key,
                      proxyName: entry.value,
                    ),
                  );
                  if (message.isNotEmpty) {
                    throw StateError('selection_restore_rejected');
                  }
                } catch (restoreError) {
                  restoreFailure ??= restoreError;
                  commonPrint.event(
                    'proxy.mode_switch.restore_failed',
                    fields: {
                      ...fields,
                      'error_type': restoreError.runtimeType.toString(),
                    },
                  );
                }
              }
              if (restoreFailure != null) {
                throw ModeSwitchRecoveryException(restoreFailure);
              }
            }
          }
        });
      });
    } catch (error) {
      if (error is ModeSwitchRecoveryException && ref.mounted) {
        await ref.read(setupActionProvider.notifier).recoverModeSwitchRuntime();
      }
      commonPrint.event(
        'proxy.mode_switch.failed',
        fields: {...fields, 'error_type': error.runtimeType.toString()},
      );
      if (error is ModeSwitchRecoveryException) {
        return isCancelled?.call() == true
            ? ModeSwitchResult.cancelled
            : ModeSwitchResult.failed;
      }
      return current() ? ModeSwitchResult.failed : ModeSwitchResult.cancelled;
    } finally {
      profileSubscription.close();
      modeSubscription.close();
      runningSubscription.close();
      coreSubscription.close();
      chainSubscription.close();
    }
  }

  Profile? _createModeSelectionProfile({
    required Profile? profile,
    required String? targetGroupName,
    required Map<String, String> selections,
    required List<Group> groups,
  }) {
    if (profile == null || !ref.mounted) return null;
    final currentGroupName = targetGroupName == GroupName.GLOBAL.name
        ? GroupName.GLOBAL.name
        : targetGroupName == null
        ? profile.currentGroupName
        : resolveRuleModeDisplayGroup(
            ruleTargetName: targetGroupName,
            currentGroupName: profile.currentGroupName,
            groups: groups,
          );
    final next = profile.copyWith(
      currentGroupName: currentGroupName,
      selectedMap: {...profile.selectedMap, ...selections},
    );
    return next == profile ? null : next;
  }

  String _currentModeSelection(Group group, Map<String, String> selectedMap) {
    final runtimeSelected = group.realNow;
    if (group.all.any((member) => member.name == runtimeSelected)) {
      return runtimeSelected;
    }
    final selected = selectedMap[group.name] ?? '';
    return group.all.any((member) => member.name == selected) ? selected : '';
  }

  @protected
  Future<List<Group>> loadModeSwitchGroups() async {
    final groups = await proxyController.getProxiesGroups(
      sortType: ref.read(proxiesStyleSettingProvider).sortType,
      delayMap: ref.read(delayDataSourceProvider),
      selectedMap: ref.read(currentProfileProvider)?.selectedMap ?? const {},
      defaultTestUrl: ref.read(appSettingProvider).testUrl,
    );
    if (groups.isEmpty) throw StateError('proxy_groups_unavailable');
    return groups;
  }

  void updateGroupsDebounce([Duration? duration]) {
    debouncer.call(FunctionTag.updateGroups, updateGroups, duration: duration);
  }

  void changeProxyDebounce(String groupName, String proxyName) {
    if (isChainProxyRuntimeName(proxyName)) return;
    _recordManualSelection(groupName, proxyName);
    final manualRevision = manualSelectionRevision;
    debouncer.call(FunctionTag.changeProxy, (
      String groupName,
      String proxyName,
    ) async {
      if (!ref.mounted || manualRevision != manualSelectionRevision) return;
      await _queueProxyChange(groupName: groupName, proxyName: proxyName);
      updateGroupsDebounce();
    }, args: [groupName, proxyName]);
  }

  Future<void> updateGroups() async {
    try {
      commonPrint.log('updateGroups');
      ref.read(groupsProvider.notifier).value = await retry(
        task: () async {
          final sortType = ref.read(
            proxiesStyleSettingProvider.select((state) => state.sortType),
          );
          final delayMap = ref.read(delayDataSourceProvider);
          final testUrl = ref.read(
            appSettingProvider.select((state) => state.testUrl),
          );
          final selectedMap = ref.read(
            currentProfileProvider.select((state) => state?.selectedMap ?? {}),
          );
          return coreController.getProxiesGroups(
            selectedMap: selectedMap,
            sortType: sortType,
            delayMap: delayMap,
            defaultTestUrl: testUrl,
          );
        },
        retryIf: (res) => res.isEmpty,
      );
    } catch (e) {
      commonPrint.log(
        'updateGroups error: $e',
        logLevel: coreFailureLogLevel(e),
      );
      ref.read(groupsProvider.notifier).value = [];
    }
  }

  void updateCurrentGroupName(String groupName) {
    final profile = ref.read(currentProfileProvider);
    if (profile == null || profile.currentGroupName == groupName) return;
    ref
        .read(profilesProvider.notifier)
        .put(profile.copyWith(currentGroupName: groupName));
  }

  void updateCurrentUnfoldSet(Set<String> value) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null) return;
    ref
        .read(profilesProvider.notifier)
        .put(currentProfile.copyWith(unfoldSet: value));
  }

  void setDelay(Delay delay) {
    ref.read(delayDataSourceProvider.notifier).setDelay(delay);
  }

  void setConnectionDelay(Delay delay) {
    ref.read(connectionDelayDataSourceProvider.notifier).setDelay(delay);
  }

  Future<bool> _applyConnectionRefresh({
    required Map<String, Object> fields,
    required bool closeConnections,
    required String reason,
  }) async {
    final diagnosticFields = {
      ...fields,
      'close_connections': closeConnections,
      'reason': reason,
    };
    final operation = closeConnections ? 'close_all' : 'reset';
    try {
      commonPrint.event(
        'connections.$operation.requested',
        fields: diagnosticFields,
      );
      if (closeConnections) {
        await proxyController.closeConnections();
      } else {
        await proxyController.resetConnections();
      }
      commonPrint.event(
        'connections.$operation.completed',
        fields: diagnosticFields,
      );
      return true;
    } catch (error) {
      commonPrint.event(
        'connections.$operation.failed',
        fields: {
          ...diagnosticFields,
          'error_type': error.runtimeType.toString(),
        },
      );
      return false;
    }
  }

  Future<bool> _resetConnectionsAfterAutomaticSelection(
    Map<String, Object> fields,
  ) {
    return _applyConnectionRefresh(
      fields: fields,
      closeConnections: false,
      reason: 'automatic_node_selection',
    );
  }

  Future<bool> applyModeSwitchConnectionPolicy(Map<String, Object> fields) {
    return _applyConnectionRefresh(
      fields: fields,
      closeConnections: false,
      reason: 'mode_switch',
    );
  }

  Future<bool> _applyManualNodeSwitchConnectionPolicy(
    Map<String, Object> fields,
  ) {
    return _applyConnectionRefresh(
      fields: fields,
      closeConnections: ref.read(appSettingProvider).closeConnections,
      reason: 'manual_node_switch',
    );
  }

  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) {
    if (isChainProxyRuntimeName(proxyName)) return Future<void>.value();
    _recordManualSelection(groupName, proxyName);
    return _queueProxyChange(groupName: groupName, proxyName: proxyName);
  }

  Future<void> _queueProxyChange({
    required String groupName,
    required String proxyName,
  }) {
    return _selectionScheduler.run(() async {
      if (!ref.mounted) return;
      await _changeProxy(groupName: groupName, proxyName: proxyName);
    });
  }

  Future<void> _changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    final fields = {
      'group_ref': diagnosticFingerprint(groupName),
      'node_ref': diagnosticFingerprint(proxyName),
    };
    commonPrint.event('proxy.selection.started', fields: fields);
    try {
      final result = await proxyController.changeProxy(
        ChangeProxyParams(groupName: groupName, proxyName: proxyName),
      );
      if (result.isNotEmpty) {
        commonPrint.event('proxy.selection.rejected', fields: fields);
        throw StateError('proxy_selection_rejected');
      }
      if (!ref.mounted) return;
      final connectionRefreshSucceeded =
          await _applyManualNodeSwitchConnectionPolicy(fields);
      commonPrint.event(
        'proxy.selection.succeeded',
        fields: {
          ...fields,
          'connection_refresh_succeeded': connectionRefreshSucceeded,
        },
      );
    } catch (error) {
      commonPrint.event(
        'proxy.selection.failed',
        fields: {
          ...fields,
          'error_type': error.runtimeType.toString(),
          'error': '$error',
        },
      );
      rethrow;
    }
    if (ref.mounted) ref.read(checkIpNumProvider.notifier).add();
  }

  Future<String> updateProvider(
    ExternalProvider provider, {
    bool showLoading = false,
  }) async {
    try {
      if (showLoading) {
        ref.read(isUpdatingProvider(provider.updatingKey).notifier).value =
            true;
      }
      final message = await coreController.updateExternalProvider(
        providerName: provider.name,
      );
      if (message.isNotEmpty) return message;
      ref
          .read(providersProvider.notifier)
          .setProvider(await coreController.getExternalProvider(provider.name));
      return '';
    } finally {
      ref.read(isUpdatingProvider(provider.updatingKey).notifier).value = false;
    }
  }
}
