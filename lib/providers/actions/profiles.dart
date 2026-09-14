part of '../action.dart';

class _ProfileFileSnapshot {
  const _ProfileFileSnapshot({required this.path, required this.bytes});

  final String path;
  final Uint8List? bytes;
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
  }) => _profileMutationScheduler.run(
    () => _syncSubscriptionProfile(
      url,
      label: label,
      replacingUrl: replacingUrl,
      loader: loader,
      effectClearer: effectClearer,
      isCurrent: isCurrent,
    ),
  );

  Future<Profile> _syncSubscriptionProfile(
    String url, {
    String? label,
    String? replacingUrl,
    Future<Profile> Function(Profile profile)? loader,
    Future<void> Function(int profileId)? effectClearer,
    bool Function()? isCurrent,
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
    final sourceSnapshot = isCurrent == null
        ? null
        : await _captureProfileFile(sourceProfile.id);
    late final Profile updatedProfile;
    try {
      ensureCurrent();
      updatedProfile =
          await (loader ?? (profile) => profile.update(isCurrent: isCurrent))(
            sourceProfile,
          );
      ensureCurrent();
    } catch (error, stackTrace) {
      if (sourceSnapshot != null) {
        await _restoreProfileFile(sourceSnapshot);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    ref.read(profilesProvider.notifier).put(updatedProfile);
    ref.read(currentProfileIdProvider.notifier).value = updatedProfile.id;
    await ref
        .read(setupActionProvider.notifier)
        .applyProfile(force: true, silence: true);
    if (replacingUrl != null && replacingUrl != normalizedUrl) {
      await removeSubscriptionProfile(
        replacingUrl,
        effectClearer: effectClearer,
      );
    }
    return updatedProfile;
  }

  Future<Profile> syncSubscriptionProfileBytes(
    Uint8List bytes, {
    required String sourceId,
    String? label,
    String? replacingUrl,
    bool removeLegacyXboardProfiles = false,
    Future<Profile> Function(Profile profile, Uint8List bytes)? loader,
    Future<void> Function(int profileId)? effectClearer,
  }) => _profileMutationScheduler.run(
    () => _syncSubscriptionProfileBytes(
      bytes,
      sourceId: sourceId,
      label: label,
      replacingUrl: replacingUrl,
      removeLegacyXboardProfiles: removeLegacyXboardProfiles,
      loader: loader,
      effectClearer: effectClearer,
    ),
  );

  Future<Profile> _syncSubscriptionProfileBytes(
    Uint8List bytes, {
    required String sourceId,
    String? label,
    String? replacingUrl,
    bool removeLegacyXboardProfiles = false,
    Future<Profile> Function(Profile profile, Uint8List bytes)? loader,
    Future<void> Function(int profileId)? effectClearer,
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
    final sourceProfile =
        existingProfile ?? Profile.normal(label: label, url: sourceId);
    final updatedProfile =
        await (loader ?? (profile, content) => profile.saveFile(content))(
          sourceProfile,
          bytes,
        );
    ref.read(profilesProvider.notifier).put(updatedProfile);
    ref.read(currentProfileIdProvider.notifier).value = updatedProfile.id;
    await ref
        .read(setupActionProvider.notifier)
        .applyProfile(force: true, silence: true);
    if (replacingUrl != null && replacingUrl != sourceId) {
      await removeSubscriptionProfile(
        replacingUrl,
        effectClearer: effectClearer,
      );
    }
    if (removeLegacyXboardProfiles) {
      await removeLegacyXboardSubscriptionProfiles(
        effectClearer: effectClearer,
      );
    }
    return updatedProfile;
  }

  Future<void> removeLegacyXboardSubscriptionProfiles({
    Future<void> Function(int profileId)? effectClearer,
  }) async {
    final legacyProfiles = ref
        .read(profilesProvider)
        .where(
          (profile) => isLegacyXboardSubscriptionProfileSource(profile.url),
        )
        .toList(growable: false);
    for (final profile in legacyProfiles) {
      await removeSubscriptionProfile(
        profile.url,
        effectClearer: effectClearer,
      );
    }
  }

  Future<void> removeSubscriptionProfile(
    String url, {
    Future<void> Function(int profileId)? effectClearer,
  }) async {
    final matchingProfiles = ref
        .read(profilesProvider)
        .where((profile) => profile.url == url)
        .toList(growable: false);
    if (matchingProfiles.isEmpty) return;
    final matchingIds = matchingProfiles.map((profile) => profile.id).toSet();
    if (matchingIds.contains(ref.read(currentProfileIdProvider))) {
      ref.read(currentProfileIdProvider.notifier).value = null;
      await ref.read(setupActionProvider.notifier).setRunning(false);
    }
    for (final profile in matchingProfiles) {
      await ref.read(profilesProvider.notifier).del(profile.id);
      await (effectClearer ?? clearEffect)(profile.id);
    }
  }

  Future<void> updateProfiles() async {
    for (final profile in ref.read(profilesProvider)) {
      if (profile.type == ProfileType.file) continue;
      await updateProfile(profile);
    }
  }

  Future<void> updateProfile(Profile profile, {bool showLoading = false}) =>
      _profileMutationScheduler.run(
        () => _updateProfile(profile, showLoading: showLoading),
      );

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
          : await _updateLegacySubscriptionProfile(profile);
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

  Future<Profile> loadProfileUpdate(
    Profile profile, {
    bool Function()? isCurrent,
  }) => profile.update(isCurrent: isCurrent);

  Future<Profile> _updateLegacySubscriptionProfile(Profile profile) async {
    final session = globalState.xboardSession;
    if (session == null) return loadProfileUpdate(profile);
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
      return loadProfileUpdate(profile);
    }
    final storage = XboardSessionStorage();
    final managedUrl = await storage.loadManagedProfileUrl();
    bool isCurrent() =>
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
    if (!isManaged) return loadProfileUpdate(profile);
    if (globalState.isOfflineMode) return profile;
    final target = session.legacySubscribeUrl;
    if (target == null) {
      throw const SubscriptionV2Exception('legacy_subscription_unavailable');
    }
    final sourceSnapshot = await _captureProfileFile(profile.id);
    try {
      if (!isCurrent()) throw StateError('profile_sync_superseded');
      commonPrint.event(
        'subscription.profile.v1.download.started',
        fields: {'endpoint_ref': apiDiagnosticEndpointRef(target)},
      );
      final updated = await loadProfileUpdate(
        profile.copyWith(url: target.toString()),
        isCurrent: isCurrent,
      );
      if (!isCurrent()) throw StateError('profile_sync_superseded');
      await storage.setManagedProfileUrl(updated.url, isCurrent: isCurrent);
      if (!isCurrent()) throw StateError('profile_sync_superseded');
      return updated;
    } catch (error, stackTrace) {
      await _restoreProfileFile(sourceSnapshot);
      Error.throwWithStackTrace(error, stackTrace);
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
