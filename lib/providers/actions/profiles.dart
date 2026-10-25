part of '../action.dart';

class _ProfileFileSnapshot {
  const _ProfileFileSnapshot({required this.path, required this.bytes});

  final String path;
  final Uint8List? bytes;
}

class _ProfileSyncSnapshot {
  const _ProfileSyncSnapshot({
    required this.profiles,
    required this.currentProfileId,
    required this.files,
  });

  final List<Profile> profiles;
  final int? currentProfileId;
  final List<_ProfileFileSnapshot> files;
}

typedef _ProfileUpdateScope = ({int id, String source, int account});

class _ProfileUpdateOperation {
  _ProfileUpdateOperation(
    this.profile,
    this.sourceRevision, {
    required this.automatic,
  });

  final Profile profile;
  int sourceRevision;
  bool automatic;
  bool started = false;
  late final Future<void> future;
}

class _ProfileUpdateFailure {
  const _ProfileUpdateFailure(this.count, this.failedAt, this.retryAfter);

  final int count;
  final DateTime failedAt;
  final DateTime retryAfter;
}

typedef _AuthenticatedProfileSource = ({int account, String source});

class _AuthenticatedProfileOperation {
  _AuthenticatedProfileOperation({
    required this.source,
    required this.generation,
    required this.allowTokenRegistration,
    required this.automatic,
    required this.forceRefresh,
    required this.originalProfile,
    required this.sourceRevision,
    required this.isCurrent,
  });

  final _AuthenticatedProfileSource source;
  final int generation;
  final bool allowTokenRegistration;
  final bool automatic;
  final bool forceRefresh;
  Profile? originalProfile;
  int sourceRevision;
  final bool Function()? isCurrent;
  Profile? committingProfile;
  int? committingSourceRevision;
  bool usedTokenRegistration = false;
  late final Future<Profile?> future;
}

class _RecentAuthenticatedProfile {
  const _RecentAuthenticatedProfile({
    required this.profile,
    required this.file,
    required this.sourceRevision,
    required this.completedAt,
    required this.usedTokenRegistration,
  });

  final Profile profile;
  final _ProfileFileSnapshot file;
  final int sourceRevision;
  final DateTime completedAt;
  final bool usedTokenRegistration;
}

final _authenticatedProfileOperationKey = Object();

@Riverpod(keepAlive: true)
class ProfilesAction extends _$ProfilesAction {
  final _profileMutationScheduler = SerialTaskScheduler();
  final _profileUpdates = <_ProfileUpdateScope, _ProfileUpdateOperation>{};
  final _automaticFailures = <_ProfileUpdateScope, _ProfileUpdateFailure>{};
  final _profileSourceRevisions = <int, int>{};
  Object? _accountIdentity;
  int _accountRevision = 0;
  final _authenticatedProfilePending =
      <(_AuthenticatedProfileSource, bool), _AuthenticatedProfileOperation>{};
  final _recentAuthenticatedProfiles =
      <_AuthenticatedProfileSource, _RecentAuthenticatedProfile>{};
  final _authenticatedProfileGenerations = <_AuthenticatedProfileSource, int>{};

  @override
  void build() {
    _accountIdentity = _currentAccountIdentity;
    globalState.xboardSessionRevisionNotifier.addListener(_accountChanged);
    ref.onDispose(() {
      globalState.xboardSessionRevisionNotifier.removeListener(_accountChanged);
    });
    ref.listen(profilesProvider, (previous, next) {
      final before = {
        for (final profile in previous ?? <Profile>[]) profile.id: profile.url,
      };
      final after = {for (final profile in next) profile.id: profile.url};
      for (final id in {...before.keys, ...after.keys}) {
        if (before[id] == after[id]) continue;
        _profileSourceRevisions[id] = (_profileSourceRevisions[id] ?? 0) + 1;
        _automaticFailures.removeWhere((scope, _) => scope.id == id);
      }
    });
  }

  Object? get _currentAccountIdentity {
    final session = globalState.xboardSession;
    return session == null
        ? null
        : (
            endpoint: session.endpoint,
            authData: session.authData,
            token: session.token,
            secure: session.secureSubscription,
          );
  }

  void _accountChanged() {
    final identity = _currentAccountIdentity;
    if (identity == _accountIdentity) return;
    _accountIdentity = identity;
    _accountRevision++;
    _automaticFailures.clear();
    _recentAuthenticatedProfiles.clear();
    _authenticatedProfilePending.clear();
    _authenticatedProfileGenerations.clear();
  }

  @visibleForTesting
  DateTime get profileUpdateNow => DateTime.now();

  @visibleForTesting
  int profileUpdateJitterSeconds(int maximum) =>
      DateTime.now().microsecondsSinceEpoch % (maximum + 1);

  void updateCurrentSelectedMap(String groupName, String proxyName) {
    if (isChainProxyRuntimeName(proxyName)) return;
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile != null &&
        currentProfile.selectedMap[groupName] != proxyName) {
      final selectedMap = Map<String, String>.from(currentProfile.selectedMap)
        ..[groupName] = proxyName;
      ref
          .read(profilesProvider.notifier)
          .put(currentProfile.copyWith(selectedMap: selectedMap));
    }
  }

  Future<void> deleteProfile(int id) async {
    await ref.read(profilesProvider.notifier).del(id);
    await clearEffect(id);
    final currentProfileId = ref.read(currentProfileIdProvider);
    if (currentProfileId == id) {
      final profiles = ref.read(profilesProvider);
      if (profiles.isNotEmpty) {
        final updateId = profiles.first.id;
        ref.read(currentProfileIdProvider.notifier).value = updateId;
      } else {
        ref.read(currentProfileIdProvider.notifier).value = null;
        ref.read(setupActionProvider.notifier).setRunning(false);
      }
    }
  }

  Future<void> autoUpdateProfiles() async {
    _accountChanged();
    if (globalState.isOfflineMode || !ref.mounted) return;
    final account = _accountRevision;
    final ids = ref
        .read(profilesProvider)
        .map((profile) => profile.id)
        .toList();
    for (final id in ids) {
      if (!ref.mounted ||
          globalState.isOfflineMode ||
          account != _accountRevision) {
        return;
      }
      final profile = ref.read(profilesProvider).getProfile(id);
      if (profile == null || !_canAutomaticallyUpdate(profile)) continue;
      try {
        await _scheduleProfileUpdate(profile, automatic: true);
      } catch (e) {
        commonPrint.log(e.toString(), logLevel: LogLevel.warning);
      }
    }
  }

  bool _canAutomaticallyUpdate(Profile profile) {
    if (!profile.autoUpdate || profile.type == ProfileType.file) return false;
    if (!_canAutomaticallyReadProfile(profile.id)) return false;
    final now = profileUpdateNow;
    final lastUpdate = profile.lastUpdateDate;
    if (lastUpdate != null &&
        lastUpdate.add(profile.autoUpdateDuration).isAfter(now)) {
      return false;
    }
    final failure = _automaticFailures[_updateScope(profile)];
    return failure == null ||
        now.isBefore(failure.failedAt) ||
        !now.isBefore(failure.retryAfter);
  }

  @visibleForTesting
  bool get canAutomaticallyReadProfiles =>
      ApiHealthService.automaticRequestsAvailable;

  @visibleForTesting
  int get automaticProfileRequestRevision =>
      ApiHealthService.automaticRequestsRevision;

  bool _canAutomaticallyReadProfile(int id) =>
      canAutomaticallyReadProfiles || id == ref.read(currentProfileIdProvider);

  _ProfileUpdateScope _updateScope(Profile profile) =>
      (id: profile.id, source: profile.url, account: _accountRevision);

  void _recordAutomaticFailure(_ProfileUpdateScope scope) {
    final count = (_automaticFailures[scope]?.count ?? 0) + 1;
    const minutes = [20, 40, 80, 160, 320, 360];
    final base = Duration(minutes: minutes[(count - 1).clamp(0, 5)]);
    final jitter = profileUpdateJitterSeconds(60).clamp(0, 60);
    final seconds = (base.inSeconds + jitter).clamp(
      0,
      const Duration(hours: 6).inSeconds,
    );
    final now = profileUpdateNow;
    _automaticFailures[scope] = _ProfileUpdateFailure(
      count,
      now,
      now.add(Duration(seconds: seconds)),
    );
  }

  Future<Profile?> runAuthenticatedSubscriptionSync(
    XboardLoginResult session, {
    required Future<Profile?> Function(bool Function() isCurrent) sync,
    required bool allowTokenRegistration,
    bool forceRefresh = false,
    bool Function()? isCurrent,
    Future<void> Function(Profile profile, bool Function() isCurrent)? onReuse,
    Profile? sourceProfile,
    bool automatic = false,
  }) async {
    _accountChanged();
    final identity = (
      endpoint: session.endpoint,
      authData: session.authData,
      token: session.token,
      secure: session.secureSubscription,
    );
    final account = _accountRevision;
    bool accountCurrent() =>
        ref.mounted &&
        !globalState.isOfflineMode &&
        account == _accountRevision &&
        identity == _currentAccountIdentity &&
        isCurrent?.call() != false;
    if (!accountCurrent()) return null;
    final source = (
      account: account,
      source: session.legacySubscribeUrl?.toString() ?? 'secure-profile',
    );
    final key = (source, allowTokenRegistration);
    final pending =
        _authenticatedProfilePending[key] ??
        (allowTokenRegistration
            ? _authenticatedProfilePending[(source, false)]
            : null);
    if (pending != null &&
        (!forceRefresh || pending.forceRefresh) &&
        _authenticatedOperationCurrent(pending)) {
      Profile? profile;
      var failed = false;
      try {
        profile = await pending.future;
      } catch (_) {
        if (pending.allowTokenRegistration == allowTokenRegistration) rethrow;
        failed = true;
      }
      if (!accountCurrent()) return null;
      if (!failed) {
        if (!pending.automatic || automatic || profile == null) return profile;
        return runAuthenticatedSubscriptionSync(
          session,
          sync: sync,
          allowTokenRegistration: allowTokenRegistration,
          forceRefresh: forceRefresh,
          isCurrent: isCurrent,
          onReuse: onReuse,
        );
      }
    }
    if (forceRefresh) {
      _authenticatedProfileGenerations[source] =
          (_authenticatedProfileGenerations[source] ?? 0) + 1;
      _recentAuthenticatedProfiles.remove(source);
    }
    final generation = _authenticatedProfileGenerations[source] ?? 0;
    bool current() =>
        accountCurrent() &&
        generation == (_authenticatedProfileGenerations[source] ?? 0);
    final loose = !forceRefresh && !allowTokenRegistration
        ? _authenticatedProfilePending[(source, true)]
        : null;
    final operation = _AuthenticatedProfileOperation(
      source: source,
      generation: generation,
      allowTokenRegistration: allowTokenRegistration,
      automatic: automatic,
      forceRefresh: forceRefresh,
      originalProfile: null,
      sourceRevision: 0,
      isCurrent: current,
    );
    final completer = Completer<Profile?>();
    operation.future = completer.future;
    operation.future.ignore();
    _authenticatedProfilePending[key] = operation;
    try {
      if (loose != null && _authenticatedOperationCurrent(loose)) {
        try {
          await loose.future;
        } catch (_) {}
      }
      if (!current()) {
        completer.complete(null);
        return null;
      }
      final recent = !forceRefresh
          ? _recentAuthenticatedProfiles[source]
          : null;
      final reuse =
          recent != null &&
          (allowTokenRegistration || !recent.usedTokenRegistration) &&
          await _canReuseAuthenticatedProfile(recent, current);
      final original = reuse
          ? recent.profile
          : sourceProfile ?? await _managedAuthenticatedProfile(session);
      operation.originalProfile = original;
      operation.sourceRevision = original == null
          ? 0
          : _profileSourceRevisions[original.id] ?? 0;
      if (!current()) {
        completer.complete(null);
        return null;
      }
      final profile = await runZoned(() async {
        bool guardedCurrent() => _authenticatedOperationCurrent(operation);
        if (!reuse) return sync(guardedCurrent);
        final restored = await _activateReusedAuthenticatedProfile(
          recent,
          guardedCurrent,
        );
        if (!guardedCurrent()) return null;
        await onReuse?.call(restored, guardedCurrent);
        return guardedCurrent() ? restored : null;
      }, zoneValues: {_authenticatedProfileOperationKey: operation});
      if (!reuse &&
          profile != null &&
          _authenticatedOperationCurrent(operation)) {
        final file = await _captureProfileFile(profile.id);
        if (_authenticatedOperationCurrent(operation) && file.bytes != null) {
          final committed = ref.read(profilesProvider).getProfile(profile.id);
          if (committed == null || committed.url != profile.url) {
            completer.complete(null);
            return null;
          }
          final completed = _RecentAuthenticatedProfile(
            profile: committed,
            file: file,
            sourceRevision: _profileSourceRevisions[profile.id] ?? 0,
            completedAt: profileUpdateNow,
            usedTokenRegistration: operation.usedTokenRegistration,
          );
          if (await _canReuseAuthenticatedProfile(completed, current)) {
            _recentAuthenticatedProfiles[source] = completed;
          }
        }
      }
      final result = _authenticatedOperationCurrent(operation) ? profile : null;
      completer.complete(result);
      return result;
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      if (identical(_authenticatedProfilePending[key], operation)) {
        _authenticatedProfilePending.remove(key);
      }
    }
  }

  bool _authenticatedOperationCurrent(
    _AuthenticatedProfileOperation operation,
  ) {
    if (!ref.mounted ||
        globalState.isOfflineMode ||
        operation.source.account != _accountRevision ||
        operation.isCurrent?.call() == false ||
        operation.generation !=
            (_authenticatedProfileGenerations[operation.source] ?? 0)) {
      return false;
    }
    final original = operation.originalProfile;
    if (original == null) return true;
    final latest = ref.read(profilesProvider).getProfile(original.id);
    if (latest == null) return false;
    if ((_profileSourceRevisions[original.id] ?? 0) ==
        operation.sourceRevision) {
      return latest.url == original.url;
    }
    final committing = operation.committingProfile;
    return committing != null &&
        (_profileSourceRevisions[original.id] ?? 0) ==
            operation.committingSourceRevision &&
        latest.url == committing.url &&
        latest.lastUpdateDate == committing.lastUpdateDate;
  }

  Future<Profile?> _managedAuthenticatedProfile(
    XboardLoginResult session,
  ) async {
    final managed = await XboardSessionStorage().loadManagedProfileUrl();
    final source = session.legacySubscribeUrl?.toString();
    for (final profile in ref.read(profilesProvider)) {
      if (profile.url == source || profile.url == managed) return profile;
    }
    return null;
  }

  Future<bool> _canReuseAuthenticatedProfile(
    _RecentAuthenticatedProfile recent,
    bool Function() isCurrent,
  ) async {
    final age = profileUpdateNow.difference(recent.completedAt);
    if (!isCurrent() || age.isNegative || age >= const Duration(seconds: 30)) {
      return false;
    }
    final current = ref.read(profilesProvider).getProfile(recent.profile.id);
    if (current == null ||
        current.url != recent.profile.url ||
        current.lastUpdateDate != recent.profile.lastUpdateDate ||
        (_profileSourceRevisions[current.id] ?? 0) != recent.sourceRevision) {
      return false;
    }
    final ruleAccountKey = globalState.xboardRuleAccountKey;
    if (ruleAccountKey != null &&
        await database.rulesDao.getProfileAccountKey(current.id) !=
            ruleAccountKey) {
      return false;
    }
    final file = File(recent.file.path);
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    final expected = recent.file.bytes!;
    if (bytes.length != expected.length) return false;
    for (var index = 0; index < bytes.length; index++) {
      if (bytes[index] != expected[index]) return false;
    }
    return isCurrent();
  }

  Future<Profile> _activateReusedAuthenticatedProfile(
    _RecentAuthenticatedProfile recent,
    bool Function() isCurrent,
  ) {
    final profile = ref.read(profilesProvider).getProfile(recent.profile.id);
    if (profile == null) throw StateError('profile_sync_superseded');
    Future<Profile> load() async {
      if (!await _canReuseAuthenticatedProfile(recent, isCurrent)) {
        throw StateError('profile_sync_superseded');
      }
      return profile;
    }

    if (isSubscriptionV2ProfileSource(profile.url)) {
      return syncSubscriptionProfileBytes(
        recent.file.bytes!,
        sourceId: profile.url,
        ruleAccountKey: globalState.xboardRuleAccountKey,
        usedTokenRegistration: recent.usedTokenRegistration,
        loader: (_, _) => load(),
        isCurrent: isCurrent,
      );
    }
    return syncSubscriptionProfile(
      profile.url,
      ruleAccountKey: globalState.xboardRuleAccountKey,
      loader: (_) => load(),
      isCurrent: isCurrent,
    );
  }

  void _markAuthenticatedProfileCommit(Profile profile) {
    final operation = Zone.current[_authenticatedProfileOperationKey];
    if (operation is _AuthenticatedProfileOperation) {
      operation.committingProfile = profile;
      final previous = ref.read(profilesProvider).getProfile(profile.id);
      operation.committingSourceRevision =
          (_profileSourceRevisions[profile.id] ?? 0) +
          (previous?.url == profile.url ? 0 : 1);
    }
  }

  void _markSubscriptionTokenRegistration(bool usedTokenRegistration) {
    final operation = Zone.current[_authenticatedProfileOperationKey];
    if (operation is _AuthenticatedProfileOperation && usedTokenRegistration) {
      operation.usedTokenRegistration = true;
    }
  }

  void putProfile(Profile profile) {
    ref.read(profilesProvider.notifier).put(profile);
    if (ref.read(currentProfileIdProvider) != null) return;
    ref.read(currentProfileIdProvider.notifier).value = profile.id;
  }

  Future<Profile> syncSubscriptionProfile(
    String url, {
    String? label,
    String? replacingUrl,
    String? ruleAccountKey,
    Future<Profile> Function(Profile profile)? loader,
    Future<void> Function(int profileId)? effectClearer,
    bool Function()? isCurrent,
    Duration? validationTimeout,
  }) {
    return _profileMutationScheduler.run(
      () => _syncSubscriptionProfile(
        url,
        label: label,
        replacingUrl: replacingUrl,
        ruleAccountKey: ruleAccountKey,
        loader: loader,
        effectClearer: effectClearer,
        isCurrent: isCurrent,
        validationTimeout: validationTimeout,
      ),
    );
  }

  Future<Profile> _syncSubscriptionProfile(
    String url, {
    String? label,
    String? replacingUrl,
    String? ruleAccountKey,
    Future<Profile> Function(Profile profile)? loader,
    Future<void> Function(int profileId)? effectClearer,
    bool Function()? isCurrent,
    Duration? validationTimeout,
  }) async {
    final subscriptionUri = Uri.tryParse(url);
    if (subscriptionUri == null ||
        !subscriptionUri.isAbsolute ||
        (subscriptionUri.scheme != 'http' &&
            subscriptionUri.scheme != 'https') ||
        subscriptionUri.host.isEmpty) {
      throw ArgumentError.value(url, 'url', 'Invalid subscription URL');
    }

    await _isolateRuleAccount(ruleAccountKey, isCurrent: isCurrent);
    final normalizedUrl = subscriptionUri.toString();
    final profiles = ref.read(profilesProvider);
    Profile? existingProfile;
    for (final profile in profiles) {
      if (profile.url == normalizedUrl &&
          await _canUseRuleAccount(profile.id, ruleAccountKey)) {
        existingProfile = profile;
        break;
      }
    }
    if (existingProfile == null && replacingUrl != null) {
      final previousUri = Uri.tryParse(replacingUrl);
      final onlyEndpointChanged =
          previousUri != null &&
          {'http', 'https'}.contains(previousUri.scheme) &&
          previousUri.host.isNotEmpty &&
          previousUri.replace(
                scheme: subscriptionUri.scheme,
                host: subscriptionUri.host,
                port: subscriptionUri.port,
              ) ==
              subscriptionUri;
      if (onlyEndpointChanged) {
        for (final profile in profiles) {
          if (profile.url == replacingUrl &&
              await _canUseRuleAccount(profile.id, ruleAccountKey)) {
            existingProfile = profile.copyWith(url: normalizedUrl);
            break;
          }
        }
      }
    }

    final sourceProfile =
        existingProfile ?? Profile.normal(label: label, url: normalizedUrl);
    void ensureCurrent() {
      if (isCurrent?.call() == false) {
        throw StateError('profile_sync_superseded');
      }
    }

    ensureCurrent();
    final sourceFileSnapshot = await _captureProfileFile(sourceProfile.id);
    _ProfileSyncSnapshot? transactionSnapshot;
    var candidateApplied = false;
    try {
      ensureCurrent();
      await ref
          .read(coreActionProvider.notifier)
          .ensureCoreForSubscription(isCurrent: isCurrent);
      ensureCurrent();
      final updatedProfile =
          await (loader ??
              (profile) => profile.update(
                isCurrent: isCurrent,
                validationTimeout: validationTimeout,
              ))(sourceProfile);

      ensureCurrent();
      if (updatedProfile.id != sourceProfile.id) {
        throw StateError('profile_sync_changed_profile_id');
      }
      transactionSnapshot = await _captureProfileSyncSnapshot(
        sourceProfileId: sourceProfile.id,
        sourceFileSnapshot: sourceFileSnapshot,
      );
      ensureCurrent();
      await _bindProfileRuleAccount(updatedProfile.id, ruleAccountKey);
      ensureCurrent();
      await ref
          .read(setupActionProvider.notifier)
          .applyProfile(
            force: true,
            silence: true,
            isCurrent: isCurrent,
            propagateErrors: true,
            profileOverride: updatedProfile,
          );
      candidateApplied = true;
      ensureCurrent();
      _markAuthenticatedProfileCommit(updatedProfile);
      await ref.read(profilesProvider.notifier).putDurable(updatedProfile);
      ensureCurrent();
      ref.read(currentProfileIdProvider.notifier).value = updatedProfile.id;
      final committedProfile = await _readCommittedSubscriptionProfile(
        updatedProfile,
        isCurrent: isCurrent,
      );
      ensureCurrent();
      if (replacingUrl != null && replacingUrl != normalizedUrl) {
        await _removeSubscriptionProfile(
          replacingUrl,
          effectClearer: effectClearer,
          isCurrent: isCurrent,
        );
      }
      ensureCurrent();
      return committedProfile;
    } catch (error, stackTrace) {
      await _rollbackProfileSync(
        transactionSnapshot,
        sourceFileSnapshot: sourceFileSnapshot,
        restoreCore: candidateApplied,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Profile> syncSubscriptionProfileBytes(
    Uint8List bytes, {
    required String sourceId,
    String? label,
    String? replacingUrl,
    String? ruleAccountKey,
    bool removeLegacyXboardProfiles = false,
    Future<Profile> Function(Profile profile, Uint8List bytes)? loader,
    Future<void> Function(int profileId)? effectClearer,
    bool Function()? isCurrent,
    Duration? validationTimeout,
    SubscriptionDiagnosticRecorder? diagnosticRecorder,
    bool usedTokenRegistration = false,
  }) {
    _markSubscriptionTokenRegistration(usedTokenRegistration);
    return _profileMutationScheduler.run(
      () => _syncSubscriptionProfileBytes(
        bytes,
        sourceId: sourceId,
        label: label,
        replacingUrl: replacingUrl,
        ruleAccountKey: ruleAccountKey,
        removeLegacyXboardProfiles: removeLegacyXboardProfiles,
        loader: loader,
        effectClearer: effectClearer,
        isCurrent: isCurrent,
        validationTimeout: validationTimeout,
        diagnosticRecorder: diagnosticRecorder,
      ),
    );
  }

  Future<Profile> _syncSubscriptionProfileBytes(
    Uint8List bytes, {
    required String sourceId,
    String? label,
    String? replacingUrl,
    String? ruleAccountKey,
    bool removeLegacyXboardProfiles = false,
    Future<Profile> Function(Profile profile, Uint8List bytes)? loader,
    Future<void> Function(int profileId)? effectClearer,
    bool Function()? isCurrent,
    Duration? validationTimeout,
    SubscriptionDiagnosticRecorder? diagnosticRecorder,
  }) async {
    if (!isSubscriptionV2ProfileSource(sourceId)) {
      throw ArgumentError.value(sourceId, 'sourceId', 'Invalid V2 source');
    }
    await _isolateRuleAccount(ruleAccountKey, isCurrent: isCurrent);
    final profiles = ref.read(profilesProvider);
    Profile? existingProfile;
    for (final profile in profiles) {
      if (profile.url == sourceId &&
          await _canUseRuleAccount(profile.id, ruleAccountKey)) {
        existingProfile = profile;
        break;
      }
    }
    if (existingProfile == null && replacingUrl != null) {
      for (final profile in profiles) {
        if (profile.url == replacingUrl &&
            (ruleAccountKey == null ||
                await database.rulesDao.getProfileAccountKey(profile.id) ==
                    ruleAccountKey)) {
          existingProfile = profile.copyWith(url: sourceId);
          break;
        }
      }
    }
    void ensureCurrent() {
      if (isCurrent?.call() == false) {
        throw StateError('profile_sync_superseded');
      }
    }

    final sourceProfile =
        existingProfile ?? Profile.normal(label: label, url: sourceId);
    ensureCurrent();
    final sourceFileSnapshot = await _captureProfileFile(sourceProfile.id);
    _ProfileSyncSnapshot? transactionSnapshot;
    var candidateApplied = false;
    try {
      ensureCurrent();
      await ref
          .read(coreActionProvider.notifier)
          .ensureCoreForSubscription(isCurrent: isCurrent);
      ensureCurrent();
      final updatedProfile = await runSubscriptionDiagnosticStage(
        stage: 'profile_validation',
        recorder: diagnosticRecorder,
        contentBytes: (_) => bytes.length,
        task: () =>
            (loader ??
            (profile, content) => profile.saveFile(
              content,
              isCurrent: isCurrent,
              validationTimeout: validationTimeout,
            ))(sourceProfile, bytes),
      );
      ensureCurrent();
      if (updatedProfile.id != sourceProfile.id) {
        throw StateError('profile_sync_changed_profile_id');
      }
      transactionSnapshot = await _captureProfileSyncSnapshot(
        sourceProfileId: sourceProfile.id,
        sourceFileSnapshot: sourceFileSnapshot,
      );
      ensureCurrent();
      await _bindProfileRuleAccount(updatedProfile.id, ruleAccountKey);
      ensureCurrent();
      late final Profile committedProfile;
      await runSubscriptionDiagnosticStage(
        stage: 'profile_write',
        recorder: diagnosticRecorder,
        contentBytes: (_) => bytes.length,
        task: () async {
          await ref
              .read(setupActionProvider.notifier)
              .applyProfile(
                force: true,
                silence: true,
                isCurrent: isCurrent,
                propagateErrors: true,
                profileOverride: updatedProfile,
              );
          candidateApplied = true;
          ensureCurrent();
          _markAuthenticatedProfileCommit(updatedProfile);
          await ref.read(profilesProvider.notifier).putDurable(updatedProfile);
          ensureCurrent();
          ref.read(currentProfileIdProvider.notifier).value = updatedProfile.id;
          committedProfile = await _readCommittedSubscriptionProfile(
            updatedProfile,
            isCurrent: isCurrent,
          );
        },
      );
      ensureCurrent();
      if (replacingUrl != null && replacingUrl != sourceId) {
        await _removeSubscriptionProfile(
          replacingUrl,
          effectClearer: effectClearer,
          isCurrent: isCurrent,
        );
      }
      ensureCurrent();
      if (removeLegacyXboardProfiles) {
        await _removeLegacyXboardSubscriptionProfiles(
          effectClearer: effectClearer,
          isCurrent: isCurrent,
        );
      }
      ensureCurrent();
      return committedProfile;
    } catch (error, stackTrace) {
      await _rollbackProfileSync(
        transactionSnapshot,
        sourceFileSnapshot: sourceFileSnapshot,
        restoreCore: candidateApplied,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Profile> _readCommittedSubscriptionProfile(
    Profile expected, {
    bool Function()? isCurrent,
  }) async {
    final profiles = await database.profilesDao.query().get();
    final committed = profiles.getProfile(expected.id);
    if (isCurrent?.call() == false ||
        ref.read(currentProfileIdProvider) != expected.id ||
        committed == null ||
        committed.url != expected.url) {
      throw StateError('profile_sync_superseded');
    }
    return committed;
  }

  Future<void> removeLegacyXboardSubscriptionProfiles({
    Future<void> Function(int profileId)? effectClearer,
    bool Function()? isCurrent,
  }) {
    return _profileMutationScheduler.run(
      () => _removeLegacyXboardSubscriptionProfiles(
        effectClearer: effectClearer,
        isCurrent: isCurrent,
      ),
    );
  }

  Future<bool> _canUseRuleAccount(int profileId, String? accountKey) async {
    if (accountKey == null) return true;
    final existingKey = await database.rulesDao.getProfileAccountKey(profileId);
    return existingKey == null || existingKey == accountKey;
  }

  Future<void> prepareRuleAccount(
    String? accountKey, {
    bool Function()? isCurrent,
  }) {
    return _profileMutationScheduler.run(
      () => _isolateRuleAccount(accountKey, isCurrent: isCurrent),
    );
  }

  Future<void> _isolateRuleAccount(
    String? accountKey, {
    bool Function()? isCurrent,
  }) async {
    if (accountKey == null) return;
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) return;
    final existingKey = await database.rulesDao.getProfileAccountKey(profileId);
    if (isCurrent?.call() == false) {
      throw StateError('profile_sync_superseded');
    }
    if (existingKey == null || existingKey == accountKey) return;
    if (ref.read(currentProfileIdProvider) != profileId) return;
    ref.read(currentProfileIdProvider.notifier).value = null;
    await ref
        .read(setupActionProvider.notifier)
        .setRunning(false, propagateErrors: true);
    if (isCurrent?.call() == false) {
      throw StateError('profile_sync_superseded');
    }
  }

  Future<void> _bindProfileRuleAccount(
    int profileId,
    String? accountKey,
  ) async {
    if (accountKey == null) return;
    await database.rulesDao.bindProfileAccount(profileId, accountKey);
    ref.invalidate(profileRuleAccountKeyProvider(profileId));
    ref.invalidate(setupStateProvider(profileId));
  }

  Future<void> _removeLegacyXboardSubscriptionProfiles({
    Future<void> Function(int profileId)? effectClearer,
    bool Function()? isCurrent,
  }) async {
    final legacyProfiles = ref
        .read(profilesProvider)
        .where(
          (profile) => isLegacyXboardSubscriptionProfileSource(profile.url),
        )
        .toList(growable: false);
    for (final profile in legacyProfiles) {
      if (isCurrent?.call() == false) {
        throw StateError('profile_sync_superseded');
      }
      await _removeSubscriptionProfile(
        profile.url,
        effectClearer: effectClearer,
        isCurrent: isCurrent,
      );
    }
  }

  Future<void> removeSubscriptionProfile(
    String url, {
    Future<void> Function(int profileId)? effectClearer,
    bool Function()? isCurrent,
  }) {
    return _profileMutationScheduler.run(
      () => _removeSubscriptionProfile(
        url,
        effectClearer: effectClearer,
        isCurrent: isCurrent,
      ),
    );
  }

  Future<void> _removeSubscriptionProfile(
    String url, {
    Future<void> Function(int profileId)? effectClearer,
    bool Function()? isCurrent,
  }) async {
    if (isCurrent?.call() == false) {
      throw StateError('profile_sync_superseded');
    }
    final matchingProfiles = ref
        .read(profilesProvider)
        .where((profile) => profile.url == url)
        .toList(growable: false);
    if (matchingProfiles.isEmpty) return;
    final matchingIds = matchingProfiles.map((profile) => profile.id).toSet();
    if (matchingIds.contains(ref.read(currentProfileIdProvider))) {
      if (isCurrent?.call() == false) {
        throw StateError('profile_sync_superseded');
      }
      ref.read(currentProfileIdProvider.notifier).value = null;
      await ref.read(setupActionProvider.notifier).setRunning(false);
    }
    for (final profile in matchingProfiles) {
      if (isCurrent?.call() == false) {
        throw StateError('profile_sync_superseded');
      }
      await ref.read(profilesProvider.notifier).del(profile.id);
      if (isCurrent?.call() == false) {
        throw StateError('profile_sync_superseded');
      }
      await (effectClearer ?? clearEffect)(profile.id);
    }
    if (isCurrent?.call() == false) {
      throw StateError('profile_sync_superseded');
    }
  }

  Future<_ProfileSyncSnapshot> _captureProfileSyncSnapshot({
    required int sourceProfileId,
    required _ProfileFileSnapshot sourceFileSnapshot,
  }) async {
    final profiles = List<Profile>.from(ref.read(profilesProvider));
    final currentProfileId = ref.read(currentProfileIdProvider);
    final files = <_ProfileFileSnapshot>[sourceFileSnapshot];
    for (final profile in profiles) {
      if (profile.id == sourceProfileId) continue;
      files.add(await _captureProfileFile(profile.id));
    }
    return _ProfileSyncSnapshot(
      profiles: profiles,
      currentProfileId: currentProfileId,
      files: files,
    );
  }

  Future<void> _rollbackProfileSync(
    _ProfileSyncSnapshot? snapshot, {
    required _ProfileFileSnapshot sourceFileSnapshot,
    required bool restoreCore,
  }) async {
    Object? firstError;
    StackTrace? firstStackTrace;
    final files = snapshot?.files ?? [sourceFileSnapshot];
    for (final file in files) {
      try {
        await _restoreProfileFile(file);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (snapshot != null) {
      try {
        await ref
            .read(profilesProvider.notifier)
            .setAllDurable(snapshot.profiles);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      } finally {
        ref.read(currentProfileIdProvider.notifier).value =
            snapshot.currentProfileId;
      }
      if (restoreCore) {
        final previousProfile = snapshot.profiles.getProfile(
          snapshot.currentProfileId,
        );
        try {
          await ref
              .read(setupActionProvider.notifier)
              .applyProfile(
                force: true,
                silence: true,
                propagateErrors: true,
                profileOverride: previousProfile,
              );
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
          commonPrint.event(
            'subscription.profile.rollback.core_failed',
            fields: {'error_type': error.runtimeType.toString()},
          );
        }
      }
    }
    if (firstError != null) {
      commonPrint.log(
        'restore profile sync transaction failed: $firstError\n$firstStackTrace',
        logLevel: LogLevel.warning,
      );
    }
  }

  Future<_ProfileFileSnapshot> _captureProfileFile(int profileId) async {
    final path = await appPath.getProfilePath(profileId.toString());
    final file = File(path);
    final bytes = await file.exists() ? await file.readAsBytes() : null;
    return _ProfileFileSnapshot(path: path, bytes: bytes);
  }

  Future<void> _restoreProfileFile(_ProfileFileSnapshot snapshot) async {
    final file = File(snapshot.path);
    final bytes = snapshot.bytes;
    if (bytes == null) {
      await file.safeDelete();
      return;
    }
    await file.safeWriteAsBytes(bytes);
  }

  Future<void> updateProfiles() async {
    for (final profile in ref.read(profilesProvider)) {
      if (profile.type == ProfileType.file) continue;
      await updateProfile(profile);
    }
  }

  Future<void> updateProfile(Profile profile, {bool showLoading = false}) {
    _accountChanged();
    return _scheduleProfileUpdate(profile, showLoading: showLoading);
  }

  Future<void> _scheduleProfileUpdate(
    Profile profile, {
    bool automatic = false,
    bool showLoading = false,
  }) {
    final scope = _updateScope(profile);
    final initial = ref.read(profilesProvider).getProfile(profile.id);
    final sourceRevision = _profileSourceRevisions[profile.id] ?? 0;
    final existing = _profileUpdates[scope];
    if (existing != null &&
        existing.sourceRevision == sourceRevision &&
        !(existing.automatic &&
            !automatic &&
            existing.started &&
            globalState.xboardSession != null) &&
        (automatic || existing.profile == profile || initial == profile)) {
      if (!automatic) existing.automatic = false;
      if (showLoading) {
        ref.read(isUpdatingProvider(profile.updatingKey).notifier).value = true;
      }
      return existing.future;
    }
    final operation = _ProfileUpdateOperation(
      profile,
      sourceRevision,
      automatic: automatic,
    );
    Future<void> execute(bool Function() transactionCurrent) =>
        _profileMutationScheduler.run(() async {
          if (!ref.mounted ||
              scope.account != _accountRevision ||
              _currentAccountIdentity != _accountIdentity) {
            return;
          }
          final latest = ref.read(profilesProvider).getProfile(profile.id);
          if (latest == null ||
              operation.sourceRevision !=
                  (_profileSourceRevisions[profile.id] ?? 0)) {
            return;
          }
          if (operation.automatic &&
              (globalState.isOfflineMode ||
                  latest.url != profile.url ||
                  !_canAutomaticallyUpdate(latest))) {
            return;
          }
          if (!operation.automatic &&
              latest.url != initial?.url &&
              latest.url != profile.url) {
            return;
          }
          final candidate = operation.automatic || profile == initial
              ? latest
              : profile.copyWith(lastUpdateDate: latest.lastUpdateDate);
          if (!operation.automatic) {
            ref.read(profilesProvider.notifier).put(candidate);
          }
          operation.sourceRevision = _profileSourceRevisions[profile.id] ?? 0;
          final requestRevision =
              operation.automatic &&
                  profile.id != ref.read(currentProfileIdProvider)
              ? automaticProfileRequestRevision
              : null;
          bool isCurrent() {
            if (!ref.mounted ||
                scope.account != _accountRevision ||
                _currentAccountIdentity != _accountIdentity ||
                globalState.isOfflineMode ||
                !transactionCurrent() ||
                operation.sourceRevision !=
                    (_profileSourceRevisions[profile.id] ?? 0)) {
              return false;
            }
            final current = ref.read(profilesProvider).getProfile(profile.id);
            return current != null &&
                (!operation.automatic ||
                    (_canAutomaticallyReadProfile(profile.id) &&
                        (requestRevision == null ||
                            requestRevision ==
                                automaticProfileRequestRevision))) &&
                current.url == candidate.url &&
                current.lastUpdateDate == candidate.lastUpdateDate;
          }

          try {
            operation.started = true;
            await _updateProfile(
              candidate,
              showLoading: showLoading,
              isCurrent: isCurrent,
              forceRefresh: !operation.automatic,
            );
            _automaticFailures.remove(scope);
          } on XboardApiRequestDeferred {
            return;
          } catch (error) {
            if (isCurrent()) _recordAutomaticFailure(scope);
            rethrow;
          }
        });
    operation.future =
        _runAutomaticAuthenticatedProfileUpdate(
          profile,
          automatic: automatic,
          execute: execute,
        ).whenComplete(() {
          if (ref.mounted) {
            ref.read(isUpdatingProvider(profile.updatingKey).notifier).value =
                false;
          }
          if (identical(_profileUpdates[scope], operation)) {
            _profileUpdates.remove(scope);
          }
        });
    _profileUpdates[scope] = operation;
    return operation.future;
  }

  Future<void> _runAutomaticAuthenticatedProfileUpdate(
    Profile profile, {
    required bool automatic,
    required Future<void> Function(bool Function() isCurrent) execute,
  }) async {
    final session = globalState.xboardSession;
    if (session == null) {
      _recentAuthenticatedProfiles.removeWhere(
        (_, recent) => recent.profile.id == profile.id,
      );
      await execute(() => true);
      return;
    }
    final managed = await _managedAuthenticatedProfile(session);
    if (managed?.id != profile.id) {
      await execute(() => true);
      return;
    }
    await runAuthenticatedSubscriptionSync(
      session,
      allowTokenRegistration: true,
      forceRefresh: !automatic,
      sourceProfile: profile,
      automatic: automatic,
      sync: (isCurrent) async {
        await execute(isCurrent);
        if (!ref.mounted) return null;
        final updated = ref.read(profilesProvider).getProfile(profile.id);
        return updated?.lastUpdateDate != profile.lastUpdateDate
            ? updated
            : null;
      },
    );
  }

  Future<void> _updateProfile(
    Profile profile, {
    bool showLoading = false,
    required bool Function() isCurrent,
    required bool forceRefresh,
  }) async {
    final snapshot = await _captureProfileFile(profile.id);
    try {
      if (!isCurrent()) throw StateError('profile_sync_superseded');
      if (showLoading) {
        ref.read(isUpdatingProvider(profile.updatingKey).notifier).value = true;
      }
      final newProfile = isSubscriptionV2ProfileSource(profile.url)
          ? await _updateSubscriptionV2Profile(
              profile,
              isCurrent: isCurrent,
              forceRefresh: forceRefresh,
            )
          : await _updateLegacySubscriptionProfile(
              profile,
              isCurrent: isCurrent,
            );
      if (!isCurrent()) throw StateError('profile_sync_superseded');
      final latest = ref.read(profilesProvider).getProfile(profile.id)!;
      _markAuthenticatedProfileCommit(newProfile);
      ref
          .read(profilesProvider.notifier)
          .put(
            latest.copyWith(
              url: newProfile.url,
              label: latest.label == profile.label
                  ? newProfile.label
                  : latest.label,
              lastUpdateDate: newProfile.lastUpdateDate,
              subscriptionInfo: newProfile.subscriptionInfo,
            ),
          );
      if (profile.id == ref.read(currentProfileIdProvider)) {
        ref
            .read(setupActionProvider.notifier)
            .applyProfileDebounce(silence: true);
      }
    } catch (error, stackTrace) {
      if (ref.mounted) {
        final latest = ref.read(profilesProvider).getProfile(profile.id);
        if (latest == null) {
          await File(snapshot.path).safeDelete();
        } else if (latest.lastUpdateDate == profile.lastUpdateDate) {
          await _restoreProfileFile(snapshot);
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (ref.mounted) {
        ref.read(isUpdatingProvider(profile.updatingKey).notifier).value =
            false;
      }
    }
  }

  Future<Profile> loadProfileUpdate(
    Profile profile, {
    bool Function()? isCurrent,
  }) => profile.update(isCurrent: isCurrent);

  Future<Profile> _updateLegacySubscriptionProfile(
    Profile profile, {
    required bool Function() isCurrent,
  }) async {
    final session = globalState.xboardSession;
    if (session == null) {
      return loadProfileUpdate(profile, isCurrent: isCurrent);
    }
    final revision = globalState.xboardSessionRevision;
    final source = session.subscribeUrl;
    final profileUri = Uri.tryParse(profile.url);
    final matchesCurrentSource =
        source != null &&
        profileUri != null &&
        profileUri.path == source.path &&
        profileUri.query == source.query;
    if (!session.secureSubscription &&
        source != null &&
        !matchesCurrentSource) {
      return loadProfileUpdate(profile, isCurrent: isCurrent);
    }
    final storage = XboardSessionStorage();
    final managedUrl = await storage.loadManagedProfileUrl();
    bool isSessionCurrent() =>
        isCurrent() &&
        globalState.isActiveXboardSession(session, revision) &&
        !globalState.isOfflineMode;
    if (!globalState.isActiveXboardSession(session, revision)) {
      throw StateError('profile_sync_superseded');
    }
    final isManaged =
        profile.url == source?.toString() ||
        (matchesCurrentSource &&
            (profile.url == managedUrl ||
                isSameApiEndpoint(profileUri, session.endpoint))) ||
        (profile.url == managedUrl &&
            (session.secureSubscription || source == null));
    if (!isManaged) return loadProfileUpdate(profile, isCurrent: isCurrent);
    if (globalState.isOfflineMode) return profile;
    final target = session.legacySubscribeUrl;
    if (target == null) {
      throw const SubscriptionV2Exception('legacy_subscription_unavailable');
    }
    if (!isSessionCurrent()) throw StateError('profile_sync_superseded');
    commonPrint.event(
      'subscription.profile.v1.download.started',
      fields: {'endpoint_ref': apiDiagnosticEndpointRef(target)},
    );
    final updated = await loadProfileUpdate(
      profile.copyWith(url: target.toString()),
      isCurrent: isSessionCurrent,
    );
    if (!isSessionCurrent()) throw StateError('profile_sync_superseded');
    await storage.setManagedProfileUrl(
      updated.url,
      isCurrent: isSessionCurrent,
    );
    if (!isSessionCurrent()) throw StateError('profile_sync_superseded');
    return updated;
  }

  Future<Profile> _updateSubscriptionV2Profile(
    Profile profile, {
    required bool Function() isCurrent,
    required bool forceRefresh,
  }) async {
    final session = globalState.xboardSession;
    if (session == null || globalState.isOfflineMode) {
      throw const SubscriptionV2Exception('authenticated_session_required');
    }
    final result = await loadSubscriptionV2Profile(
      session,
      forceRefresh: forceRefresh,
      requestScope: isCurrent,
      canRequest: isCurrent,
    );
    _markSubscriptionTokenRegistration(result?.usedTokenRegistration ?? false);
    if (!isCurrent()) throw StateError('profile_sync_superseded');
    if (result == null) {
      throw const SubscriptionV2Exception('gray_access_removed');
    }
    final updated = await profile
        .copyWith(url: result.sourceId)
        .saveFile(result.bytes, isCurrent: isCurrent);
    if (!isCurrent()) throw StateError('profile_sync_superseded');
    await XboardSessionStorage().setManagedProfileUrl(
      result.sourceId,
      isCurrent: isCurrent,
    );
    if (!isCurrent()) throw StateError('profile_sync_superseded');
    return updated;
  }

  @visibleForTesting
  Future<SubscriptionV2Profile?> loadSubscriptionV2Profile(
    XboardLoginResult session, {
    bool forceRefresh = false,
    Object? requestScope,
    bool Function()? canRequest,
  }) => SubscriptionV2Client().fetchProfile(
    endpoint: session.endpoint,
    userToken: session.token,
    appVersion: globalState.packageInfo.version,
    forceRefresh: forceRefresh,
    requestScope: requestScope,
    canRequest: canRequest,
  );

  Future<void> addProfileFormFile() async {
    final platformFile = await globalState.safeRun(picker.pickerFile);
    if (platformFile == null) return;
    final bytes = await platformFile.readBytes();
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    ref.read(currentPageLabelProvider.notifier).toProfiles();
    final profile = await globalState.loadingRun(
      tag: LoadingTag.profiles,
      () async {
        return Profile.normal(label: platformFile.name).saveFile(bytes);
      },
      title: currentAppLocalizations.addProfile,
    );
    if (profile != null) {
      putProfile(profile);
    }
  }

  Future<void> addProfileFormURL(String url) async {
    if (globalState.navigatorKey.currentState?.canPop() ?? false) {
      globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    ref.read(currentPageLabelProvider.notifier).value = PageLabel.profiles;
    final profile = await globalState.loadingRun(
      tag: LoadingTag.profiles,
      () async {
        return Profile.normal(url: url).update();
      },
      title: currentAppLocalizations.addProfile,
    );
    if (profile != null) {
      putProfile(profile);
    }
  }

  void setProfileAndAutoApply(Profile profile) {
    ref.read(profilesProvider.notifier).put(profile);
    if (profile.id == ref.read(currentProfileIdProvider)) {
      ref.read(setupActionProvider.notifier).applyProfileDebounce();
    }
  }

  Future<void> addProfileFormQrCode() async {
    final url = await globalState.safeRun(picker.pickerConfigQRCode);
    if (url == null) return;
    addProfileFormURL(url);
  }

  void reorder(List<Profile> profiles) {
    ref.read(profilesProvider.notifier).reorder(profiles);
  }

  Future<void> clearEffect(int profileId) async {
    final profilePath = await appPath.getProfilePath(profileId.toString());
    final profileFile = File(profilePath);
    final isExists = await profileFile.exists();
    if (isExists) {
      await profileFile.safeDelete(recursive: true);
    }
    final error = await coreController.clearEffect(profileId);
    if (error.isNotEmpty) {
      commonPrint.log(error, logLevel: LogLevel.warning);
    }
  }
}
