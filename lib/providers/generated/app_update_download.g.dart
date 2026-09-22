// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../app_update_download.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(appUpdateDownloadService)
final appUpdateDownloadServiceProvider = AppUpdateDownloadServiceProvider._();

final class AppUpdateDownloadServiceProvider
    extends
        $FunctionalProvider<
          AppUpdateDownloadService,
          AppUpdateDownloadService,
          AppUpdateDownloadService
        >
    with $Provider<AppUpdateDownloadService> {
  AppUpdateDownloadServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appUpdateDownloadServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appUpdateDownloadServiceHash();

  @$internal
  @override
  $ProviderElement<AppUpdateDownloadService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AppUpdateDownloadService create(Ref ref) {
    return appUpdateDownloadService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppUpdateDownloadService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppUpdateDownloadService>(value),
    );
  }
}

String _$appUpdateDownloadServiceHash() =>
    r'ce6353c57f063e5959ad18af7a86023ebf636629';

@ProviderFor(AppUpdateDownload)
final appUpdateDownloadProvider = AppUpdateDownloadProvider._();

final class AppUpdateDownloadProvider
    extends $NotifierProvider<AppUpdateDownload, AppUpdateDownloadState> {
  AppUpdateDownloadProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appUpdateDownloadProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appUpdateDownloadHash();

  @$internal
  @override
  AppUpdateDownload create() => AppUpdateDownload();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppUpdateDownloadState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppUpdateDownloadState>(value),
    );
  }
}

String _$appUpdateDownloadHash() => r'b551721d6df3005dc3624c83ec4c256aed45d8ee';

abstract class _$AppUpdateDownload extends $Notifier<AppUpdateDownloadState> {
  AppUpdateDownloadState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AppUpdateDownloadState, AppUpdateDownloadState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppUpdateDownloadState, AppUpdateDownloadState>,
              AppUpdateDownloadState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
