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

@Riverpod(keepAlive: true)
class ProfilesAction extends _$ProfilesAction {
  final _profileMutationScheduler = SerialTaskScheduler();

  @override
  void build() {}

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
    for (final profile in ref.read(profilesProvider)) {
      if (!profile.autoUpdate) continue;
      final isNotNeedUpdate = profile.lastUpdateDate
          ?.add(profile.autoUpdateDuration)
          .isBeforeNow;
      if (isNotNeedUpdate == false || profile.type == ProfileType.file) {
        continue;
      }
      try {
        await updateProfile(profile);
      } catch (e) {
        commonPrint.log(e.toString(), logLevel: LogLevel.warning);
      }
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

    final normalizedUrl = subscriptionUri.toString();
    final profiles = ref.read(profilesProvider);
    Profile? existingProfile;
    for (final profile in profiles) {
      if (profile.url == normalizedUrl) {
        existingProfile = profile;
        break;
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
      await ref.read(profilesProvider.notifier).putDurable(updatedProfile);
      ensureCurrent();
      ref.read(currentProfileIdProvider.notifier).value = updatedProfile.id;
      ensureCurrent();
      if (replacingUrl != null && replacingUrl != normalizedUrl) {
        await _removeSubscriptionProfile(
          replacingUrl,
          effectClearer: effectClearer,
          isCurrent: isCurrent,
        );
      }
      ensureCurrent();
      return updatedProfile;
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
    bool removeLegacyXboardProfiles = false,
    Future<Profile> Function(Profile profile, Uint8List bytes)? loader,
    Future<void> Function(int profileId)? effectClearer,
    bool Function()? isCurrent,
    Duration? validationTimeout,
  }) {
    return _profileMutationScheduler.run(
      () => _syncSubscriptionProfileBytes(
        bytes,
        sourceId: sourceId,
        label: label,
        replacingUrl: replacingUrl,
        removeLegacyXboardProfiles: removeLegacyXboardProfiles,
        loader: loader,
        effectClearer: effectClearer,
        isCurrent: isCurrent,
        validationTimeout: validationTimeout,
      ),
    );
  }

  Future<Profile> _syncSubscriptionProfileBytes(
    Uint8List bytes, {
    required String sourceId,
    String? label,
    String? replacingUrl,
    bool removeLegacyXboardProfiles = false,
    Future<Profile> Function(Profile profile, Uint8List bytes)? loader,
    Future<void> Function(int profileId)? effectClearer,
    bool Function()? isCurrent,
    Duration? validationTimeout,
  }) async {
    if (!isSubscriptionV2ProfileSource(sourceId)) {
      throw ArgumentError.value(sourceId, 'sourceId', 'Invalid V2 source');
    }
    final profiles = ref.read(profilesProvider);
    Profile? existingProfile;
    for (final profile in profiles) {
      if (profile.url == sourceId) {
        existingProfile = profile;
        break;
      }
    }
    if (existingProfile == null && replacingUrl != null) {
      for (final profile in profiles) {
        if (profile.url == replacingUrl) {
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
      final updatedProfile =
          await (loader ??
              (profile, content) => profile.saveFile(
                content,
                isCurrent: isCurrent,
                validationTimeout: validationTimeout,
              ))(sourceProfile, bytes);
      ensureCurrent();
      if (updatedProfile.id != sourceProfile.id) {
        throw StateError('profile_sync_changed_profile_id');
      }
      transactionSnapshot = await _captureProfileSyncSnapshot(
        sourceProfileId: sourceProfile.id,
        sourceFileSnapshot: sourceFileSnapshot,
      );
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
      await ref.read(profilesProvider.notifier).putDurable(updatedProfile);
      ensureCurrent();
      ref.read(currentProfileIdProvider.notifier).value = updatedProfile.id;
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
      return updatedProfile;
    } catch (error, stackTrace) {
      await _rollbackProfileSync(
        transactionSnapshot,
        sourceFileSnapshot: sourceFileSnapshot,
        restoreCore: candidateApplied,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
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
    return _profileMutationScheduler.run(
      () => _updateProfile(profile, showLoading: showLoading),
    );
  }

  Future<void> _updateProfile(
    Profile profile, {
    bool showLoading = false,
  }) async {
    try {
      if (showLoading) {
        ref.read(isUpdatingProvider(profile.updatingKey).notifier).value = true;
      }
      ref.read(profilesProvider.notifier).put(profile);
      final newProfile = isSubscriptionV2ProfileSource(profile.url)
          ? await _updateSubscriptionV2Profile(profile)
          : await profile.update();
      ref.read(profilesProvider.notifier).put(newProfile);
      if (profile.id == ref.read(currentProfileIdProvider)) {
        ref
            .read(setupActionProvider.notifier)
            .applyProfileDebounce(silence: true);
      }
    } finally {
      ref.read(isUpdatingProvider(profile.updatingKey).notifier).value = false;
    }
  }

  Future<Profile> _updateSubscriptionV2Profile(Profile profile) async {
    final session = globalState.xboardSession;
    if (session == null || globalState.isOfflineMode) {
      throw const SubscriptionV2Exception('authenticated_session_required');
    }
    final result = await SubscriptionV2Client().fetchProfile(
      endpoint: session.endpoint,
      userToken: session.token,
      appVersion: globalState.packageInfo.version,
    );
    if (result == null) {
      throw const SubscriptionV2Exception('gray_access_removed');
    }
    final updated = await profile
        .copyWith(url: result.sourceId)
        .saveFile(result.bytes);
    await XboardSessionStorage().setManagedProfileUrl(result.sourceId);
    return updated;
  }

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
