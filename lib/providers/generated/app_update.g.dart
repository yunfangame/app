// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../app_update.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(updateService)
final appUpdateServiceProvider = UpdateServiceProvider._();

final class UpdateServiceProvider
    extends
        $FunctionalProvider<
          AppUpdateService,
          AppUpdateService,
          AppUpdateService
        >
    with $Provider<AppUpdateService> {
  UpdateServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appUpdateServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$updateServiceHash();

  @$internal
  @override
  $ProviderElement<AppUpdateService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppUpdateService create(Ref ref) {
    return updateService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppUpdateService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppUpdateService>(value),
    );
  }
}

String _$updateServiceHash() => r'4436f6ab03194b70cfcf055b4535cfef882fb5a7';

@ProviderFor(appUpdatePlatform)
final appUpdatePlatformProvider = AppUpdatePlatformProvider._();

final class AppUpdatePlatformProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  AppUpdatePlatformProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appUpdatePlatformProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appUpdatePlatformHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return appUpdatePlatform(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$appUpdatePlatformHash() => r'0dddb010c0e3b9d3a84a12ba2d12e315e3e2bb75';

@ProviderFor(appUpdateCurrentVersion)
final appUpdateCurrentVersionProvider = AppUpdateCurrentVersionProvider._();

final class AppUpdateCurrentVersionProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  AppUpdateCurrentVersionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appUpdateCurrentVersionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appUpdateCurrentVersionHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return appUpdateCurrentVersion(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$appUpdateCurrentVersionHash() =>
    r'5e7f245d963fe88c28e7a515731c7fe0f5a9885a';

@ProviderFor(AppUpdate)
final appUpdateProvider = AppUpdateProvider._();

final class AppUpdateProvider
    extends $NotifierProvider<AppUpdate, AppUpdateState> {
  AppUpdateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appUpdateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appUpdateHash();

  @$internal
  @override
  AppUpdate create() => AppUpdate();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppUpdateState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppUpdateState>(value),
    );
  }
}

String _$appUpdateHash() => r'1ec52725c04001d28601e7cf287dc9d68a4c2c8f';

abstract class _$AppUpdate extends $Notifier<AppUpdateState> {
  AppUpdateState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AppUpdateState, AppUpdateState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppUpdateState, AppUpdateState>,
              AppUpdateState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
