part of '../action.dart';

enum HongKongSelectionResult { selected, unavailable, failed, cancelled }

@Riverpod(keepAlive: true)
class ProxiesAction extends _$ProxiesAction {
  final _selectionScheduler = SerialTaskScheduler();
  int _hongKongSelectionRevision = 0;
  int _manualSelectionRevision = 0;

  @override
  void build() {}

  @protected
  CoreController get proxyController => coreController;

  int get hongKongSelectionRevision => _hongKongSelectionRevision;
  int get manualSelectionRevision => _manualSelectionRevision;

  void cancelHongKongSelection({bool manual = false}) {
    _hongKongSelectionRevision++;
    if (manual) _manualSelectionRevision++;
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
                await _applyNodeSwitchConnectionPolicy(selectionFields);
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

  void updateGroupsDebounce([Duration? duration]) {
    debouncer.call(FunctionTag.updateGroups, updateGroups, duration: duration);
  }

  void changeProxyDebounce(String groupName, String proxyName) {
    cancelHongKongSelection(manual: true);
    final manualRevision = manualSelectionRevision;
    debouncer.call(FunctionTag.changeProxy, (
      String groupName,
      String proxyName,
    ) async {
      if (!ref.mounted || manualRevision != manualSelectionRevision) return;
      await changeProxy(groupName: groupName, proxyName: proxyName);
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

  Future<bool> _applyNodeSwitchConnectionPolicy(
    Map<String, Object> fields,
  ) async {
    final closeConnections = ref.read(appSettingProvider).closeConnections;
    final diagnosticFields = {
      ...fields,
      'close_connections': closeConnections,
      'reason': 'node_switch',
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

  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) {
    cancelHongKongSelection(manual: true);
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
      final connectionRefreshSucceeded = await _applyNodeSwitchConnectionPolicy(
        fields,
      );
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
