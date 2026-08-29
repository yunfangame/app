part of '../action.dart';

@Riverpod(keepAlive: true)
class ProfilesAction extends _$ProfilesAction {
  @override
  void build() {}

  void updateCurrentSelectedMap(String groupName, String proxyName) {
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

  /// Downloads an authenticated subscription through the normal FlClash
  /// profile pipeline, selects it, and waits until the core applies its nodes.
  ///
  /// A profile with the exact same subscription URL is updated in place so
  /// repeated sign-ins do not create duplicates. Nothing is persisted until
  /// the subscription has downloaded and passed core validation.
  Future<Profile> syncSubscriptionProfile(
    String url, {
    String? label,
    String? replacingUrl,
    Future<Profile> Function(Profile profile)? loader,
    Future<void> Function(int profileId)? effectClearer,
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
    final updatedProfile = await (loader ?? (profile) => profile.update())(
      sourceProfile,
    );

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

  Future<void> updateProfile(
    Profile profile, {
    bool showLoading = false,
  }) async {
    try {
      if (showLoading) {
        ref.read(isUpdatingProvider(profile.updatingKey).notifier).value = true;
      }
      ref.read(profilesProvider.notifier).put(profile);
      final newProfile = await profile.update();
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
