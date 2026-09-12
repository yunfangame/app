import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/common/application_bootstrap.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/login_routing_coordinator.dart';
import 'package:fl_clash/common/system_dns.dart';
import 'package:fl_clash/common/xboard_login_persistence.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/hotkey_manager.dart';
import 'package:fl_clash/manager/manager.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:fl_clash/widgets/xboard_marquee_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/pages.dart';

enum _AuthenticationBootstrap { loading, login, home }

class Application extends ConsumerStatefulWidget {
  const Application({super.key});

  @override
  ConsumerState<Application> createState() => ApplicationState();
}

class ApplicationState extends ConsumerState<Application> {
  static const _authenticationBootstrapTimeout = Duration(seconds: 60);
  static const _applicationReadinessTimeout = Duration(seconds: 20);
  static const _profileValidationTimeout = Duration(seconds: 15);
  static const _profileSyncTimeout = Duration(seconds: 30);
  Timer? _autoUpdateProfilesTaskTimer;
  bool _preHasVpn = false;
  bool _isOpeningRegister = false;
  bool _isOpeningForgotPassword = false;
  LoginFormPrefill? _loginPrefill;
  bool _initialRememberMe = false;
  bool _initialAutoLogin = false;
  String? _rememberedLoginEmail;
  bool _logoutInProgress = false;
  bool _offlineAvailable = false;
  _AuthenticationBootstrap _authenticationBootstrap =
      _AuthenticationBootstrap.loading;
  final _xboardAuthService = XboardAuthService(
    subscriptionV2Client: SubscriptionV2Client(),
  );
  final _xboardSessionStorage = XboardSessionStorage(
    secretStore: createPlatformSecretStringStore(),
    onDiagnostic: (event, fields) => commonPrint.event(event, fields: fields),
  );
  late final _loginPersistence = XboardLoginPersistence(
    storage: _xboardSessionStorage,
    onDiagnostic: (event, fields) => commonPrint.event(event, fields: fields),
  );
  final _authenticationBootstrapController =
      AuthenticationBootstrapController();
  final _applicationReadinessGate = ApplicationReadinessGate();
  late final LoginRoutingCoordinator _loginRouting;
  LoginRoutingAttempt? _loginRoutingAttempt;
  XboardLoginResult? _loginRoutingSession;
  int? _postLoginProfileSyncRevision;
  int? _deferredProfileSyncRevision;
  int? _authenticationBootstrapSessionRevision;
  final _managedProfileSources = <String>{};

  void _beginDefaultLoginRouting(XboardLoginResult session) {
    final revision = globalState.xboardSessionRevision;
    final proxiesAction = ref.read(proxiesActionProvider.notifier);
    late final int manualSelectionRevision;
    _loginRoutingSession = session;
    _loginRoutingAttempt = _loginRouting.begin(
      isSessionCurrent: () =>
          mounted &&
          !_logoutInProgress &&
          globalState.isActiveXboardSession(session, revision) &&
          proxiesAction.manualSelectionRevision == manualSelectionRevision,
    );
    manualSelectionRevision = proxiesAction.manualSelectionRevision;
    commonPrint.event(
      'auth.routing.started',
      fields: {'session_revision': revision, 'mode': Mode.rule.name},
    );
  }

  void _selectDefaultLoginNode(
    XboardLoginResult session, {
    Profile? expectedProfile,
    bool applyProfile = false,
  }) {
    final attempt = _loginRoutingAttempt;
    if (attempt == null ||
        !identical(session, _loginRoutingSession) ||
        !_loginRouting.isCurrent(attempt)) {
      return;
    }
    final proxiesAction = ref.read(proxiesActionProvider.notifier);
    var selectionRevision = proxiesAction.hongKongSelectionRevision;
    var profile = ref.read(currentProfileProvider);
    if (expectedProfile != null &&
        !loginRoutingProfileMatches(expectedProfile, profile)) {
      commonPrint.event(
        'auth.routing.discarded',
        fields: {'reason': 'applied_profile_changed'},
      );
      return;
    }
    bool canStart() =>
        proxiesAction.hongKongSelectionRevision == selectionRevision &&
        ref.read(currentProfileProvider) == profile &&
        ref.read(patchClashConfigProvider).mode == Mode.rule;
    unawaited(
      _loginRouting.select<HongKongSelectionResult>(
        attempt,
        prepare: () async {
          final readiness = await _applicationReadinessGate.wait();
          if (readiness != ApplicationReadiness.ready) {
            throw StateError('application_not_ready_${readiness.name}');
          }
          if (!_loginRouting.isCurrent(attempt)) return;
          if (!ref.read(initProvider) ||
              ref.read(coreStatusProvider) != CoreStatus.connected) {
            throw StateError('login_routing_core_unavailable');
          }
          if (applyProfile && canStart()) {
            final previousProfile = profile;
            await ref
                .read(setupActionProvider.notifier)
                .applyProfile(force: true, silence: true);
            if (!_loginRouting.isCurrent(attempt)) return;
            final appliedProfile = ref.read(currentProfileProvider);
            if (!loginRoutingProfileMatches(
              previousProfile,
              appliedProfile,
              allowContentRefresh: true,
            )) {
              return;
            }
            profile = appliedProfile;
            selectionRevision = proxiesAction.hongKongSelectionRevision;
          }
        },
        canStart: canStart,
        select: (isCancelled) => proxiesAction.selectHongKongForMode(
          Mode.rule,
          isCancelled: () =>
              isCancelled() ||
              ref.read(currentProfileIdProvider) != profile?.id,
        ),
        onResult: (result) {
          commonPrint.event(
            'auth.routing.completed',
            fields: {'mode': Mode.rule.name, 'result': result.name},
          );
          switch (result) {
            case HongKongSelectionResult.unavailable:
              _showStartupMessage(
                currentAppLocalizations.hongKongNodesUnavailable,
                isCurrent: () => _loginRouting.isCurrent(attempt),
              );
            case HongKongSelectionResult.failed:
              _showStartupMessage(
                currentAppLocalizations.hongKongSelectionFailed,
                isCurrent: () => _loginRouting.isCurrent(attempt),
              );
            case HongKongSelectionResult.selected:
            case HongKongSelectionResult.cancelled:
              break;
          }
        },
        onError: (error) {
          commonPrint.event(
            'auth.routing.failed',
            fields: {'error_type': error.runtimeType.toString()},
          );
          _showStartupMessage(
            currentAppLocalizations.hongKongSelectionFailed,
            isCurrent: () => _loginRouting.isCurrent(attempt),
          );
        },
      ),
    );
  }

  void _openHome() {
    globalState.navigatorKey.currentState?.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomePage()),
    );
  }

  Future<void> _loadXboardNodes(
    XboardLoginResult session, {
    bool ignoreOfflineMode = false,
  }) async {
    if (globalState.isOfflineMode && !ignoreOfflineMode) return;
    final revision = globalState.xboardSessionRevision;
    commonPrint.event(
      'subscription.nodes.fetch.started',
      fields: {'session_revision': revision},
    );
    try {
      final nodes = await _xboardAuthService.fetchNodes(
        endpoint: session.endpoint,
        authData: session.authData,
      );
      if (!globalState.setXboardNodesForSession(session, revision, nodes)) {
        commonPrint.event(
          'subscription.nodes.fetch.discarded',
          fields: {'session_revision': revision},
        );
        return;
      }
      commonPrint.event(
        'subscription.nodes.fetch.succeeded',
        fields: {'node_count': nodes.length, 'session_revision': revision},
      );
      await _xboardSessionStorage.saveOfflineCache(
        session: session,
        nodes: nodes,
      );
      if (!globalState.isActiveXboardSession(session, revision)) return;
      _offlineAvailable = true;
    } catch (error, stackTrace) {
      commonPrint.event(
        'subscription.nodes.fetch.failed',
        fields: {
          'error_type': error.runtimeType.toString(),
          'error': '$error',
          'session_revision': revision,
        },
      );
      globalState.setXboardNodesForSession(session, revision, const []);
      commonPrint.log(
        'load XBoard nodes failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
    }
  }

  bool _isAuthenticationBootstrapCurrent(int revision) {
    return mounted &&
        _authenticationBootstrap == _AuthenticationBootstrap.loading &&
        _authenticationBootstrapController.isCurrent(revision);
  }

  bool _completeAuthenticationBootstrap(
    int revision,
    _AuthenticationBootstrap destination,
  ) {
    if (!mounted || !_authenticationBootstrapController.complete(revision)) {
      return false;
    }
    final bootstrapSessionRevision = _authenticationBootstrapSessionRevision;
    _authenticationBootstrapSessionRevision = null;
    if (destination == _AuthenticationBootstrap.login &&
        bootstrapSessionRevision != null &&
        globalState.xboardSessionRevision == bootstrapSessionRevision) {
      _loginRouting.cancel();
      _loginRoutingAttempt = null;
      _loginRoutingSession = null;
      _deferredProfileSyncRevision = null;
      globalState.clearXboardSession();
    }
    setState(() {
      _authenticationBootstrap = destination;
    });
    return true;
  }

  Future<void> _restoreRememberedSession(int bootstrapRevision) async {
    try {
      final storedSession = await _loginPersistence.load();
      if (!_isAuthenticationBootstrapCurrent(bootstrapRevision)) return;
      _applyRememberedLogin(storedSession);
      final offlineCache = await _xboardSessionStorage.loadOfflineCache();
      if (!_isAuthenticationBootstrapCurrent(bootstrapRevision)) return;
      final offlineRequested = await _xboardSessionStorage.loadOfflineMode();
      if (!_isAuthenticationBootstrapCurrent(bootstrapRevision)) return;
      final hasProfiles = ref.read(profilesProvider).isNotEmpty;
      _offlineAvailable =
          hasProfiles &&
          offlineCache != null &&
          offlineCache.isUsableAt(DateTime.now());
      if (offlineRequested && _offlineAvailable) {
        final session = offlineCache!.toSession();
        globalState.activateXboardSession(session, nodes: offlineCache.nodes);
        _beginDefaultLoginRouting(session);
        globalState.setOfflineMode(true);
        _completeAuthenticationBootstrap(
          bootstrapRevision,
          _AuthenticationBootstrap.home,
        );
        _selectDefaultLoginNode(session, applyProfile: true);
        return;
      }
      if (offlineRequested) {
        await _xboardSessionStorage.setOfflineMode(false);
        if (!_isAuthenticationBootstrapCurrent(bootstrapRevision)) return;
      }
      if (!storedSession.canAutoLogin) {
        _completeAuthenticationBootstrap(
          bootstrapRevision,
          _AuthenticationBootstrap.login,
        );
        return;
      }
      try {
        final session = await _xboardAuthService.restoreSession(
          preferredEndpoint: storedSession.endpoint!,
          token: storedSession.token!,
          authData: storedSession.authData!,
          isAdmin: storedSession.isAdmin,
          secureSubscription: storedSession.secureSubscription,
        );
        if (!_isAuthenticationBootstrapCurrent(bootstrapRevision)) return;
        final sessionRevision = globalState.activateXboardSession(session);
        _authenticationBootstrapSessionRevision = sessionRevision;
        _beginDefaultLoginRouting(session);
        _startPostLoginProfileSync(session, sessionRevision);
        globalState.setOfflineMode(false);
        await _xboardSessionStorage.setOfflineMode(false);
        if (!_isAuthenticationBootstrapCurrent(bootstrapRevision)) return;
        await _loadXboardNodes(session, ignoreOfflineMode: true);
        if (!_isAuthenticationBootstrapCurrent(bootstrapRevision) ||
            !globalState.isActiveXboardSession(session, sessionRevision)) {
          return;
        }
        if (!_completeAuthenticationBootstrap(
          bootstrapRevision,
          _AuthenticationBootstrap.home,
        )) {
          return;
        }
        globalState.requestXboardAnnouncementAutoPrompt();
        _startPostLoginProfileSync(session, sessionRevision);
      } on XboardAuthException catch (error) {
        if (!_isAuthenticationBootstrapCurrent(bootstrapRevision)) return;
        final sessionExpired =
            error.failure == XboardAuthFailure.authenticationRejected;
        if (sessionExpired) {
          await _loginPersistence.invalidateSession();
          if (!_isAuthenticationBootstrapCurrent(bootstrapRevision)) return;
          _initialAutoLogin = false;
          _rememberedLoginEmail = null;
        }
        final completed = _completeAuthenticationBootstrap(
          bootstrapRevision,
          _AuthenticationBootstrap.login,
        );
        if (!completed) return;
        _showStartupMessage(
          sessionExpired
              ? currentAppLocalizations.loginSessionExpired
              : error.failure == XboardAuthFailure.subscriptionUnavailable
              ? currentAppLocalizations.subscriptionImportFailed
              : currentAppLocalizations.automaticLoginUnavailable,
        );
      }
    } catch (error) {
      commonPrint.event(
        'auth.bootstrap.failed',
        fields: {'error_type': error.runtimeType.toString(), 'error': '$error'},
      );
      final completed = _completeAuthenticationBootstrap(
        bootstrapRevision,
        _AuthenticationBootstrap.login,
      );
      if (!completed) return;
      _showStartupMessage(currentAppLocalizations.automaticLoginUnavailable);
    }
  }

  Future<void> _retryDeferredProfileSync() async {
    final session = globalState.xboardSession;
    final sessionRevision = globalState.xboardSessionRevision;
    if (session == null ||
        _deferredProfileSyncRevision != sessionRevision ||
        globalState.isOfflineMode) {
      return;
    }
    _deferredProfileSyncRevision = null;
    bool isCurrent() =>
        mounted &&
        !_logoutInProgress &&
        globalState.isActiveXboardSession(session, sessionRevision);
    try {
      final profile = await _syncSubscriptionProfile(session, sessionRevision);
      if (!isCurrent() || profile == null) return;
      _selectDefaultLoginNode(session, expectedProfile: profile);
      if (!isCurrent()) return;
      globalState.requestXboardAnnouncementAutoPrompt();
    } on XboardAuthException catch (error) {
      if (!isCurrent()) return;
      commonPrint.event(
        'auth.post_login.sync.failed',
        fields: {
          'failure': error.failure.name,
          'error_type': error.runtimeType.toString(),
        },
      );
      _showStartupMessage(
        currentAppLocalizations.subscriptionImportFailed,
        isCurrent: isCurrent,
      );
    } catch (error, stackTrace) {
      commonPrint.event(
        'auth.post_login.sync.failed',
        fields: {'error_type': error.runtimeType.toString(), 'error': '$error'},
      );
      commonPrint.log(
        'retry deferred profile sync failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
    }
  }

  Future<XboardLoginResult> _loginWithRememberedSession(String email) async {
    final accountRef = diagnosticFingerprint(email);
    commonPrint.event(
      'auth.remembered_login.started',
      fields: {'account_ref': accountRef},
    );
    final stored = await _loginPersistence.load();
    if (!stored.canRestoreForEmail(email)) {
      _rememberedLoginEmail = null;
      throw XboardAuthException(
        failure: XboardAuthFailure.authenticationRejected,
        message: currentAppLocalizations.loginSessionExpired,
      );
    }
    try {
      final session = await _xboardAuthService.restoreSession(
        preferredEndpoint: stored.endpoint!,
        token: stored.token!,
        authData: stored.authData!,
        isAdmin: stored.isAdmin,
        secureSubscription: stored.secureSubscription,
      );
      if (!mounted || _logoutInProgress) return session;
      globalState.activateXboardSession(session);
      _beginDefaultLoginRouting(session);
      _startPostLoginProfileSync(session, globalState.xboardSessionRevision);
      await _loadXboardNodes(session, ignoreOfflineMode: true);
      commonPrint.event(
        'auth.remembered_login.succeeded',
        fields: {'account_ref': accountRef},
      );
      return session;
    } on XboardAuthException catch (error) {
      if (error.failure == XboardAuthFailure.authenticationRejected) {
        _rememberedLoginEmail = null;
        _initialAutoLogin = false;
        try {
          await _loginPersistence.invalidateSession();
        } catch (storageError) {
          commonPrint.event(
            'auth.remembered_login.clear_failed',
            fields: {'error_type': storageError.runtimeType.toString()},
          );
        }
      }
      commonPrint.event(
        'auth.remembered_login.failed',
        fields: {
          'account_ref': accountRef,
          'failure': error.failure.name,
          ...?error.diagnostic?.toDiagnosticFields(),
        },
      );
      rethrow;
    }
  }

  void _showStartupMessage(String message, {bool Function()? isCurrent}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || isCurrent?.call() == false) return;
      final currentContext = globalState.navigatorKey.currentContext;
      if (currentContext == null || !currentContext.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(currentContext);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  Future<void> _saveAuthenticatedSession(
    XboardLoginResult session,
    String email,
    String password,
    bool rememberMe,
    bool autoLogin,
  ) {
    if (!mounted ||
        _logoutInProgress ||
        !identical(session, globalState.xboardSession)) {
      return Future.value();
    }
    final sessionRevision = globalState.xboardSessionRevision;
    globalState.setOfflineMode(false);
    final saving = _loginPersistence.saveAuthenticated(
      session: session,
      email: email,
      password: password,
      rememberMe: rememberMe,
      autoLogin: autoLogin,
    );
    _applyRememberedLogin(_loginPersistence.state);
    runPostAuthenticationTask(
      task: () => _finishAuthenticatedSessionPersistence(
        session,
        sessionRevision,
        saving,
      ),
      onError: (error, stackTrace) {
        commonPrint.event(
          'auth.post_login.persistence.failed',
          fields: {
            'error_type': error.runtimeType.toString(),
            'error': '$error',
          },
        );
        commonPrint.log(
          'finish authenticated session persistence failed: $error, $stackTrace',
          logLevel: LogLevel.warning,
        );
      },
    );
    _startPostLoginProfileSync(session, sessionRevision);
    globalState.requestXboardAnnouncementAutoPrompt();
    return Future.value();
  }

  Future<void> _finishAuthenticatedSessionPersistence(
    XboardLoginResult session,
    int sessionRevision,
    Future<bool> saving,
  ) async {
    final saved = await saving;
    if (!mounted ||
        !globalState.isActiveXboardSession(session, sessionRevision)) {
      return;
    }
    _applyRememberedLogin(_loginPersistence.state);
    if (!saved) {
      commonPrint.event(
        'auth.credentials.save.degraded',
        fields: {'session_revision': sessionRevision},
      );
    }
    try {
      await _xboardSessionStorage.setOfflineMode(false);
    } catch (error) {
      commonPrint.event(
        'auth.offline_preference.clear_failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
    }
  }

  void _startPostLoginProfileSync(
    XboardLoginResult session,
    int sessionRevision,
  ) {
    if (_postLoginProfileSyncRevision == sessionRevision) return;
    _postLoginProfileSyncRevision = sessionRevision;
    ref.read(loadingProvider(LoadingTag.subscriptionProfile).notifier).start();
    runPostAuthenticationTask(
      task: () async {
        try {
          await _finishPostLoginProfileSync(session, sessionRevision);
        } finally {
          if (mounted && _postLoginProfileSyncRevision == sessionRevision) {
            await ref
                .read(loadingProvider(LoadingTag.subscriptionProfile).notifier)
                .stop();
          }
        }
      },
      onError: (error, stackTrace) {
        commonPrint.event(
          'auth.post_login.sync.failed',
          fields: {
            'error_type': error.runtimeType.toString(),
            'error': '$error',
          },
        );
        commonPrint.log(
          'post-login profile sync failed: $error, $stackTrace',
          logLevel: LogLevel.warning,
        );
      },
    );
  }

  Future<void> _finishPostLoginProfileSync(
    XboardLoginResult session,
    int sessionRevision,
  ) async {
    final profile = await _syncSubscriptionProfileForLogin(
      session,
      sessionRevision,
      showFailureMessage: false,
    );
    if (!mounted ||
        !globalState.isActiveXboardSession(session, sessionRevision) ||
        profile == null) {
      return;
    }
    _selectDefaultLoginNode(session, expectedProfile: profile);
  }

  Future<Profile?> _syncSubscriptionProfile(
    XboardLoginResult session,
    int sessionRevision,
  ) async {
    var operationActive = true;
    bool isCurrent() =>
        operationActive &&
        mounted &&
        !_logoutInProgress &&
        globalState.isActiveXboardSession(session, sessionRevision);
    try {
      return await _runSubscriptionProfileSync(
        session,
        sessionRevision,
        isCurrent,
      ).timeout(
        _profileSyncTimeout,
        onTimeout: () {
          operationActive = false;
          throw TimeoutException(
            'subscription_profile_sync_timeout',
            _profileSyncTimeout,
          );
        },
      );
    } on TimeoutException catch (error) {
      commonPrint.event(
        'subscription.profile.sync.timed_out',
        fields: {
          'timeout_ms': _profileSyncTimeout.inMilliseconds,
          'error': '$error',
        },
      );
      throw XboardAuthException(
        failure: XboardAuthFailure.subscriptionUnavailable,
        message: currentAppLocalizations.subscriptionImportFailed,
        endpoint: session.endpoint,
      );
    } finally {
      operationActive = false;
    }
  }

  Future<Profile?> _syncSubscriptionProfileForLogin(
    XboardLoginResult session,
    int sessionRevision, {
    bool showFailureMessage = true,
  }) async {
    try {
      return await _syncSubscriptionProfile(session, sessionRevision);
    } on XboardAuthException catch (error) {
      if (error.failure != XboardAuthFailure.subscriptionUnavailable) rethrow;
      bool isCurrent() =>
          mounted &&
          !_logoutInProgress &&
          globalState.isActiveXboardSession(session, sessionRevision);
      if (!isCurrent()) return null;
      commonPrint.event(
        'auth.profile_sync.degraded',
        fields: {'failure': error.failure.name},
      );
      if (showFailureMessage) {
        _showStartupMessage(
          currentAppLocalizations.subscriptionImportFailed,
          isCurrent: isCurrent,
        );
      }
      return null;
    }
  }

  Future<Profile?> _runSubscriptionProfileSync(
    XboardLoginResult session,
    int sessionRevision,
    bool Function() isCurrent,
  ) async {
    final readiness = await _applicationReadinessGate.wait();
    if (!isCurrent()) {
      commonPrint.event(
        'subscription.profile.sync.discarded',
        fields: {'stage': 'application_readiness'},
      );
      return null;
    }
    if (readiness != ApplicationReadiness.ready) {
      if (readiness == ApplicationReadiness.timedOut) {
        _deferredProfileSyncRevision = sessionRevision;
      }
      commonPrint.event(
        'subscription.profile.sync.skipped',
        fields: {'reason': 'application_${readiness.name}'},
      );
      return null;
    }
    if (_deferredProfileSyncRevision == sessionRevision) {
      _deferredProfileSyncRevision = null;
    }
    commonPrint.event(
      'subscription.profile.sync.started',
      fields: {'secure_subscription': session.secureSubscription},
    );
    try {
      final planName = session.subscription.plan?.name?.trim();
      final previousUrl = await _xboardSessionStorage.loadManagedProfileUrl();
      if (!isCurrent()) return null;
      final label = planName == null || planName.isEmpty
          ? currentAppLocalizations.brandName
          : planName;
      final secureProfile = await SubscriptionV2Client().fetchProfile(
        endpoint: session.endpoint,
        userToken: session.token,
        appVersion: globalState.packageInfo.version,
        allowTokenRegistration: !session.secureSubscription,
      );
      if (!isCurrent()) return null;
      if (secureProfile != null) {
        _managedProfileSources.add(secureProfile.sourceId);
        final profile = await ref
            .read(profilesActionProvider.notifier)
            .syncSubscriptionProfileBytes(
              secureProfile.bytes,
              sourceId: secureProfile.sourceId,
              label: label,
              replacingUrl: previousUrl,
              removeLegacyXboardProfiles: true,
              isCurrent: isCurrent,
              validationTimeout: _profileValidationTimeout,
              diagnosticRecorder: (event, fields) =>
                  commonPrint.event(event, fields: fields),
            );
        if (!isCurrent()) return null;
        await _xboardSessionStorage.setManagedProfileUrl(
          secureProfile.sourceId,
        );
        if (!isCurrent()) return null;
        commonPrint.event(
          'subscription.profile.sync.succeeded',
          fields: {
            'protocol': 'v2',
            'content_bytes': secureProfile.bytes.length,
          },
        );
        return profile;
      }
      if (session.secureSubscription) {
        throw const SubscriptionV2Exception('secure_profile_unavailable');
      }
      final legacyUrl = session.subscribeUrl;
      if (legacyUrl == null) {
        throw const SubscriptionV2Exception('legacy_subscription_unavailable');
      }
      final subscriptionUrl = legacyUrl.toString();
      if (!isCurrent()) return null;
      _managedProfileSources.add(subscriptionUrl);
      final profile = await ref
          .read(profilesActionProvider.notifier)
          .syncSubscriptionProfile(
            subscriptionUrl,
            label: label,
            replacingUrl: previousUrl,
            isCurrent: isCurrent,
            validationTimeout: _profileValidationTimeout,
          );
      if (!isCurrent()) return null;
      await _xboardSessionStorage.setManagedProfileUrl(subscriptionUrl);
      if (!isCurrent()) return null;
      commonPrint.event(
        'subscription.profile.sync.succeeded',
        fields: {'protocol': 'v1'},
      );
      return profile;
    } catch (error, stackTrace) {
      if (!isCurrent()) {
        commonPrint.event(
          'subscription.profile.sync.discarded',
          fields: {'stage': 'profile_mutation'},
        );
        return null;
      }
      commonPrint.event(
        'subscription.profile.sync.failed',
        fields: {
          'error_type': error.runtimeType.toString(),
          'error': '$error',
          'secure_subscription': session.secureSubscription,
        },
      );
      commonPrint.log(
        'sync XBoard subscription profile failed: $error, $stackTrace',
      );
      throw XboardAuthException(
        failure: XboardAuthFailure.subscriptionUnavailable,
        message: currentAppLocalizations.subscriptionImportFailed,
        endpoint: session.endpoint,
      );
    }
  }

  void _applyRememberedLogin(XboardStoredSession stored) {
    _loginPrefill = stored.rememberMe && stored.email != null
        ? LoginFormPrefill(
            email: stored.email!,
            password: stored.password ?? '',
          )
        : null;
    _initialRememberMe = stored.rememberMe;
    _initialAutoLogin = stored.autoLogin;
    _rememberedLoginEmail = stored.canRestore ? stored.email : null;
  }

  Future<void> _clearRememberedSession() async {
    final clearing = _loginPersistence.forget();
    _applyRememberedLogin(_loginPersistence.state);
    if (!await clearing) {
      _showStartupMessage(currentAppLocalizations.rememberedLoginClearFailed);
    }
  }

  Future<void> _disableAutomaticLogin() async {
    final disabling = _loginPersistence.disableAutoLogin();
    _initialAutoLogin = false;
    if (!await disabling) {
      _showStartupMessage(currentAppLocalizations.rememberedLoginClearFailed);
    }
  }

  Future<void> _logoutXboard() async {
    if (_logoutInProgress) return;
    _logoutInProgress = true;
    _loginRouting.cancel();
    _loginRoutingAttempt = null;
    _loginRoutingSession = null;
    _postLoginProfileSyncRevision = null;
    ref.read(loadingProvider(LoadingTag.subscriptionProfile).notifier).value =
        false;
    _deferredProfileSyncRevision = null;
    try {
      await _performLogoutXboard();
    } finally {
      _logoutInProgress = false;
    }
  }

  Future<void> _performLogoutXboard() async {
    commonPrint.event('auth.logout.requested');
    final rememberedLogin = await _loginPersistence.prepareForLogout();
    _applyRememberedLogin(rememberedLogin);
    final activeSession = globalState.xboardSession;
    final activeSubscriptionUrl = activeSession?.subscribeUrl?.toString();
    String? managedProfileUrl;
    try {
      managedProfileUrl = await _xboardSessionStorage.loadManagedProfileUrl();
    } catch (error) {
      commonPrint.event(
        'auth.logout.profile_reference.failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
    }
    final subscriptionUrls = <String>{
      ?activeSubscriptionUrl,
      ?managedProfileUrl,
      ..._managedProfileSources,
    };
    try {
      await ref.read(systemActionProvider.notifier).handleLogout();
    } catch (error, stackTrace) {
      commonPrint.log(
        'cleanup logout resources failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
    }
    if (activeSession != null && activeSession.token.isNotEmpty) {
      try {
        await SubscriptionV2Client().revokeDevice(
          endpoint: activeSession.endpoint,
          userToken: activeSession.token,
        );
      } catch (error, stackTrace) {
        commonPrint.log(
          'clear V2 device credential failed: $error, $stackTrace',
          logLevel: LogLevel.warning,
        );
      }
    }
    globalState.clearXboardSession();
    for (final url in subscriptionUrls) {
      try {
        await ref
            .read(profilesActionProvider.notifier)
            .removeSubscriptionProfile(url);
      } catch (error, stackTrace) {
        commonPrint.log(
          'clear XBoard subscription profile failed: $error, $stackTrace',
          logLevel: LogLevel.warning,
        );
      }
    }
    _managedProfileSources.removeAll(subscriptionUrls);
    var cleanupFailed = false;
    for (final cleanup in [
      _xboardSessionStorage.clearManagedProfileUrl,
      _xboardSessionStorage.clearOfflineCache,
    ]) {
      try {
        await cleanup();
      } catch (error) {
        cleanupFailed = true;
        commonPrint.event(
          'auth.logout.cache_cleanup.failed',
          fields: {'error_type': error.runtimeType.toString()},
        );
      }
    }
    globalState.setOfflineMode(false);
    _offlineAvailable = false;
    _rememberedLoginEmail = null;
    _applyRememberedLogin(rememberedLogin);
    _initialAutoLogin = false;
    commonPrint.event(
      'auth.logout.completed',
      fields: {
        'remember_requested': rememberedLogin.rememberMe,
        'email_present': rememberedLogin.email?.isNotEmpty ?? false,
        'password_present': rememberedLogin.password?.isNotEmpty ?? false,
        'storage_error': rememberedLogin.hasStorageError,
        'cache_cleanup_failed': cleanupFailed,
      },
    );
    if (!mounted) return;
    setState(() {
      _authenticationBootstrap = _AuthenticationBootstrap.login;
    });
    final locale = ref.read(appSettingProvider).locale;
    unawaited(
      globalState.navigatorKey.currentState?.pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => _buildLoginPage(locale)),
        (_) => false,
      ),
    );
  }

  Future<bool> _enableOfflineMode() async {
    if (ref.read(profilesProvider).isEmpty) return false;
    final session = globalState.xboardSession;
    if (session != null && session.authData.isNotEmpty) {
      await _xboardSessionStorage.saveOfflineCache(
        session: session,
        nodes: globalState.xboardNodes,
      );
    }
    final cache = await _xboardSessionStorage.loadOfflineCache();
    if (cache == null || !cache.isUsableAt(DateTime.now())) return false;
    await _xboardSessionStorage.setOfflineMode(true);
    if (!mounted || _logoutInProgress) return false;
    final cachedSession = cache.toSession();
    globalState.activateXboardSession(cachedSession, nodes: cache.nodes);
    _beginDefaultLoginRouting(cachedSession);
    globalState.setOfflineMode(true);
    if (mounted) setState(() => _offlineAvailable = true);
    _selectDefaultLoginNode(cachedSession, applyProfile: true);
    return true;
  }

  Future<void> _openLoginForOnlineRestore() async {
    if (!mounted) return;
    _applyRememberedLogin(_loginPersistence.state);
    final locale = ref.read(appSettingProvider).locale;
    await globalState.navigatorKey.currentState?.pushReplacement<void, void>(
      MaterialPageRoute<void>(builder: (_) => _buildLoginPage(locale)),
    );
  }

  Future<bool> _restoreOnlineMode() async {
    final storedSession = await _loginPersistence.load();
    if (!storedSession.canRestore) {
      await _openLoginForOnlineRestore();
      return false;
    }
    try {
      final session = await _xboardAuthService.restoreSession(
        preferredEndpoint: storedSession.endpoint!,
        token: storedSession.token!,
        authData: storedSession.authData!,
        isAdmin: storedSession.isAdmin,
        secureSubscription: storedSession.secureSubscription,
      );
      globalState.activateXboardSession(session);
      await _loadXboardNodes(session, ignoreOfflineMode: true);
      final sessionRevision = globalState.xboardSessionRevision;
      await _syncSubscriptionProfile(session, sessionRevision);
      await _xboardSessionStorage.setOfflineMode(false);
      globalState.setOfflineMode(false);
      globalState.requestXboardAnnouncementAutoPrompt();
      return true;
    } on XboardAuthException catch (error) {
      if (error.failure == XboardAuthFailure.authenticationRejected) {
        await _loginPersistence.invalidateSession();
        await _openLoginForOnlineRestore();
        return false;
      }
      rethrow;
    }
  }

  Future<bool> _refreshXboardSubscription() {
    return _refreshXboardData(
      retryWhenUnchanged: true,
      refreshNodeMetadata: false,
    );
  }

  Future<bool> _refreshXboardNodes() {
    return _refreshXboardData(
      retryWhenUnchanged: false,
      refreshNodeMetadata: true,
    );
  }

  Future<bool> _refreshXboardData({
    required bool retryWhenUnchanged,
    required bool refreshNodeMetadata,
  }) async {
    if (globalState.isOfflineMode) return false;
    final activeSession = globalState.xboardSession;
    if (activeSession == null || activeSession.authData.isEmpty) return false;
    final activeRevision = globalState.xboardSessionRevision;
    final activeEmail = _loginPersistence.state.email;
    final retryDelays = retryWhenUnchanged
        ? const [Duration.zero, Duration(seconds: 1), Duration(seconds: 2)]
        : const [Duration.zero];
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < retryDelays.length; attempt++) {
      final delay = retryDelays[attempt];
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (!globalState.isActiveXboardSession(activeSession, activeRevision)) {
        return false;
      }
      try {
        final subscription = await _xboardAuthService.fetchSubscription(
          endpoint: activeSession.endpoint,
          authData: activeSession.authData,
          userToken: activeSession.token,
          secureSubscription: activeSession.secureSubscription,
        );
        if (!globalState.isActiveXboardSession(activeSession, activeRevision)) {
          return false;
        }
        final isLastAttempt = attempt == retryDelays.length - 1;
        if (retryWhenUnchanged &&
            !isLastAttempt &&
            _sameSubscriptionState(activeSession.subscription, subscription)) {
          continue;
        }
        final refreshedToken = subscription.token?.trim();
        final updatedSession = XboardLoginResult(
          endpoint: activeSession.endpoint,
          token: refreshedToken == null || refreshedToken.isEmpty
              ? activeSession.token
              : refreshedToken,
          authData: activeSession.authData,
          isAdmin: activeSession.isAdmin,
          subscription: subscription,
          secureSubscription: activeSession.secureSubscription,
          rawData: activeSession.rawData,
        );
        final updatedRevision = globalState.activateXboardSession(
          updatedSession,
          nodes: globalState.xboardNodes,
        );
        if (refreshNodeMetadata) {
          await _loadXboardNodes(updatedSession);
        }
        if (!globalState.isActiveXboardSession(
          updatedSession,
          updatedRevision,
        )) {
          return false;
        }
        final nodes = globalState.xboardNodes;
        try {
          if (activeEmail != null) {
            await _xboardSessionStorage.updateStoredToken(
              updatedSession.token,
              email: activeEmail,
              expectedToken: activeSession.token,
            );
          }
          await _xboardSessionStorage.saveOfflineCache(
            session: updatedSession,
            nodes: nodes,
          );
          _offlineAvailable = true;
        } catch (error, stackTrace) {
          commonPrint.log(
            'cache refreshed XBoard subscription failed: $error, $stackTrace',
            logLevel: LogLevel.warning,
          );
        }
        await _syncSubscriptionProfile(updatedSession, updatedRevision);
        return true;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (error is XboardAuthException &&
            error.failure == XboardAuthFailure.authenticationRejected) {
          break;
        }
      }
    }
    commonPrint.log(
      'refresh XBoard data failed: '
      '$lastError, $lastStackTrace',
      logLevel: LogLevel.warning,
    );
    return false;
  }

  bool _sameSubscriptionState(
    XboardSubscriptionData previous,
    XboardSubscriptionData current,
  ) {
    return previous.planId == current.planId &&
        previous.uploadBytes == current.uploadBytes &&
        previous.downloadBytes == current.downloadBytes &&
        previous.transferEnableBytes == current.transferEnableBytes &&
        previous.expiredAtEpochSeconds == current.expiredAtEpochSeconds &&
        previous.nextResetAtEpochSeconds == current.nextResetAtEpochSeconds;
  }

  Future<void> _openOfflineHome() async {
    final enabled = await _enableOfflineMode();
    if (!enabled || !mounted) return;
    _openHome();
  }

  Future<void> _openRegister() async {
    if (_isOpeningRegister) return;
    _isOpeningRegister = true;
    try {
      final config = await _xboardAuthService.loadGuestConfig();
      globalState.xboardGuestConfig = config;
      if (!mounted) return;
      final registration = await globalState.navigatorKey.currentState?.push(
        MaterialPageRoute<RegisterFormData>(
          builder: (_) => RegisterPage(
            config: config,
            onSendVerificationCode: (email) =>
                _xboardAuthService.sendEmailVerification(email: email),
            onRegister: (data) async {
              await _xboardAuthService.register(
                email: data.email,
                password: data.password,
                emailCode: data.emailCode ?? '',
              );
            },
          ),
        ),
      );
      if (!mounted || registration == null) return;
      setState(() {
        _loginPrefill = LoginFormPrefill(
          email: registration.email,
          password: registration.password,
        );
      });
      final messenger = ScaffoldMessenger.maybeOf(
        globalState.navigatorKey.currentContext!,
      );
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(context.appLocalizations.registrationSuccess)),
        );
    } on XboardAuthException catch (error) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(
        globalState.navigatorKey.currentContext!,
      );
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      _isOpeningRegister = false;
    }
  }

  Future<void> _openForgotPassword() async {
    if (_isOpeningForgotPassword) return;
    _isOpeningForgotPassword = true;
    try {
      final email = await globalState.navigatorKey.currentState?.push<String>(
        MaterialPageRoute<String>(
          builder: (_) => ForgotPasswordPage(
            onSendVerificationCode: (email) => _xboardAuthService
                .sendEmailVerification(email: email, isForgetPassword: true),
            onResetPassword: (data) => _xboardAuthService.resetPassword(
              email: data.email,
              password: data.password,
              emailCode: data.emailCode,
            ),
          ),
        ),
      );
      if (!mounted || email == null) return;
      setState(() {
        _loginPrefill = LoginFormPrefill(email: email, password: '');
      });
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.appLocalizations.passwordResetSuccess),
          ),
        );
    } finally {
      _isOpeningForgotPassword = false;
    }
  }

  final _pageTransitionsTheme = const PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: commonSharedXPageTransitions,
      TargetPlatform.windows: commonSharedXPageTransitions,
      TargetPlatform.linux: commonSharedXPageTransitions,
      TargetPlatform.macOS: commonSharedXPageTransitions,
    },
  );

  ColorScheme _getAppColorScheme({
    required Brightness brightness,
    int? primaryColor,
  }) {
    return ref.read(genColorSchemeProvider(brightness));
  }

  @override
  void initState() {
    super.initState();
    final proxiesAction = ref.read(proxiesActionProvider.notifier);
    _loginRouting = LoginRoutingCoordinator(
      resetToRule: () =>
          ref.read(setupActionProvider.notifier).changeModeOnly(Mode.rule),
      cancelSelection: proxiesAction.cancelHongKongSelection,
    );
    globalState.logoutXboard = _logoutXboard;
    globalState.enableOfflineMode = _enableOfflineMode;
    globalState.restoreOnlineMode = _restoreOnlineMode;
    globalState.refreshXboardSubscription = _refreshXboardSubscription;
    globalState.refreshXboardNodes = _refreshXboardNodes;
    _applicationReadinessGate.startTimeout(
      timeout: _applicationReadinessTimeout,
      onTimeout: () {
        commonPrint.event(
          'app.attach.timed_out',
          fields: {
            'platform': Platform.operatingSystem,
            'timeout_ms': _applicationReadinessTimeout.inMilliseconds,
          },
        );
      },
    );
    final authenticationBootstrapRevision = _authenticationBootstrapController
        .begin(
          timeout: _authenticationBootstrapTimeout,
          onTimeout: (revision) {
            if (!_completeAuthenticationBootstrap(
              revision,
              _AuthenticationBootstrap.login,
            )) {
              return;
            }
            commonPrint.event(
              'auth.bootstrap.timed_out',
              fields: {
                'timeout_ms': _authenticationBootstrapTimeout.inMilliseconds,
              },
            );
          },
        );
    unawaited(_xboardAuthService.prepareApiConfiguration());
    unawaited(_restoreRememberedSession(authenticationBootstrapRevision));
    SystemNavigator.setFrameworkHandlesBack(true);
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      if (globalState.navigatorKey.currentContext != null) {
        try {
          await globalState.attach();
          final late =
              _applicationReadinessGate.status == ApplicationReadiness.timedOut;
          _applicationReadinessGate.ready();
          commonPrint.event(
            'app.ready',
            fields: {
              'platform': Platform.operatingSystem,
              'app_version': globalState.packageInfo.version,
              'build_number': globalState.packageInfo.buildNumber,
              'late': late,
            },
          );
          if (late) unawaited(_retryDeferredProfileSync());
        } catch (error, stackTrace) {
          _applicationReadinessGate.fail();
          commonPrint.event(
            'app.attach.failed',
            fields: {
              'platform': Platform.operatingSystem,
              'error_type': error.runtimeType.toString(),
              'error': '$error',
            },
          );
          commonPrint.log(
            'attach application failed: $error, $stackTrace',
            logLevel: LogLevel.warning,
          );
        }
      } else {
        exit(0);
      }
      if (!mounted) return;
      _autoUpdateProfilesTask();
      _initLink();
      app?.initShortcuts();
    });
  }

  Widget _buildLoginPage(String? locale) {
    return LoginPage(
      onLogin: _openHome,
      rememberedEmail: _rememberedLoginEmail,
      restoreRemembered: _loginWithRememberedSession,
      authenticate: (email, password) async {
        final accountRef = diagnosticFingerprint(email);
        commonPrint.event(
          'auth.login.started',
          fields: {'account_ref': accountRef},
        );
        try {
          final session = await _xboardAuthService.login(
            email: email,
            password: password,
            appVersion: globalState.packageInfo.version,
          );
          if (!mounted || _logoutInProgress) return session;
          globalState.activateXboardSession(session);
          _beginDefaultLoginRouting(session);
          _startPostLoginProfileSync(
            session,
            globalState.xboardSessionRevision,
          );
          await _loadXboardNodes(session, ignoreOfflineMode: true);
          commonPrint.event(
            'auth.login.succeeded',
            fields: {
              'account_ref': accountRef,
              'secure_subscription': session.secureSubscription,
              'node_count': globalState.xboardNodes.length,
            },
          );
          return session;
        } catch (error) {
          commonPrint.event(
            'auth.login.failed',
            fields: {
              'account_ref': accountRef,
              'error_type': error.runtimeType.toString(),
              'error': '$error',
              if (error is XboardAuthException)
                ...?error.diagnostic?.toDiagnosticFields(),
            },
          );
          rethrow;
        }
      },
      onAuthenticated: _saveAuthenticatedSession,
      onLanguagePressed: ToolLocaleSelector.show,
      onThemePressed: ToolThemeSelector.show,
      onSupportPressed: CustomerServiceSheet.show,
      appVersion: globalState.packageInfo.version,
      configuredLocale: locale,
      prefill: _loginPrefill,
      initialRememberMe: _initialRememberMe,
      initialAutoLogin: _initialAutoLogin,
      onRememberMeDisabled: () {
        unawaited(_clearRememberedSession());
      },
      onAutomaticLoginDisabled: () {
        unawaited(_disableAutomaticLogin());
      },
      onRegisterPressed: _openRegister,
      onForgotPasswordPressed: _openForgotPassword,
      offlineAvailable: _offlineAvailable,
      onOfflinePressed: _openOfflineHome,
      onExportLogs: () => ref.read(logsProvider.notifier).exportLogs(),
    );
  }

  void _initLink() {
    linkManager.initAppLinksListen((url) async {
      final res = await globalState.showMessage(
        title: currentAppLocalizations.addProfile,
        message: TextSpan(
          children: [
            TextSpan(text: currentAppLocalizations.doYouWantToPass),
            TextSpan(
              text: ' $url ',
              style: TextStyle(
                color: context.colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: context.colorScheme.primary,
              ),
            ),
            TextSpan(text: currentAppLocalizations.createProfile),
          ],
        ),
      );
      if (res != true) return;
      ref.read(profilesActionProvider.notifier).addProfileFormURL(url);
    });
  }

  void _autoUpdateProfilesTask() {
    if (!mounted) return;
    _autoUpdateProfilesTaskTimer = Timer(const Duration(minutes: 20), () async {
      if (!mounted) return;
      if (!globalState.isOfflineMode) {
        await ref.read(profilesActionProvider.notifier).autoUpdateProfiles();
      }
      if (!mounted) return;
      _autoUpdateProfilesTask();
    });
  }

  Widget _buildPlatformState({required Widget child}) {
    if (system.isDesktop) {
      return WindowManager(
        child: TrayManager(
          child: HotKeyManager(child: ProxyManager(child: child)),
        ),
      );
    }
    return AndroidManager(child: TileManager(child: child));
  }

  Widget _buildState({required Widget child}) {
    return AppStateManager(
      child: CoreManager(
        child: ConnectivityManager(
          onConnectivityChanged: (results) async {
            commonPrint.log('connectivityChanged ${results.toString()}');
            unawaited(systemDnsCoordinator?.resync() ?? Future.value());
            ref.read(systemActionProvider.notifier).updateLocalIp();
            final hasVpn = results.contains(ConnectivityResult.vpn);
            final hasPhysicalNetwork = hasPhysicalConnectivity(results);
            commonPrint.event(
              'network.connectivity.changed',
              fields: {
                'transports': results.map((item) => item.name).toList(),
                'has_vpn': hasVpn,
                'physical_available': hasPhysicalNetwork,
              },
            );
            if (system.isDesktop) {
              unawaited(
                ref
                    .read(setupActionProvider.notifier)
                    .handlePhysicalNetworkAvailability(hasPhysicalNetwork),
              );
            }
            if (_preHasVpn == hasVpn) {
              ref.read(checkIpNumProvider.notifier).add();
            }
            _preHasVpn = hasVpn;
          },
          child: child,
        ),
      ),
    );
  }

  Widget _buildPlatformApp({required Widget child}) {
    if (system.isDesktop) {
      return WindowHeaderContainer(child: child);
    }
    return VpnManager(child: child);
  }

  Widget _buildApp({required Widget child}) {
    return StatusManager(child: ThemeManager(child: child));
  }

  @override
  Widget build(context) {
    return Consumer(
      builder: (_, ref, _) {
        final locale = ref.watch(
          appSettingProvider.select((state) => state.locale),
        );
        final themeProps = ref.watch(themeSettingProvider);
        final home = switch (_authenticationBootstrap) {
          _AuthenticationBootstrap.loading => const _LoginBootstrapPage(),
          _AuthenticationBootstrap.home => const HomePage(),
          _AuthenticationBootstrap.login => _buildLoginPage(locale),
        };
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: globalState.navigatorKey,
          onNavigationNotification: (_) => true,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          builder: (_, child) {
            return XboardMarqueeHost(
              child: AppEnvManager(
                child: _buildApp(
                  child: _buildPlatformState(
                    child: _buildState(child: _buildPlatformApp(child: child!)),
                  ),
                ),
              ),
            );
          },
          scrollBehavior: BaseScrollBehavior(),
          title: appName,
          locale: utils.getApplicationLocale(
            locale,
            isAndroid: system.isAndroid,
          ),
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          themeMode: themeProps.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            pageTransitionsTheme: _pageTransitionsTheme,
            colorScheme: _getAppColorScheme(
              brightness: Brightness.light,
              primaryColor: themeProps.primaryColor,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            pageTransitionsTheme: _pageTransitionsTheme,
            colorScheme: _getAppColorScheme(
              brightness: Brightness.dark,
              primaryColor: themeProps.primaryColor,
            ).toPureBlack(themeProps.pureBlack),
          ),
          home: home,
        );
      },
    );
  }

  @override
  void dispose() {
    _authenticationBootstrapController.dispose();
    _applicationReadinessGate.dispose();
    _loginRouting.dispose();
    linkManager.destroy();
    _autoUpdateProfilesTaskTimer?.cancel();
    globalState.logoutXboard = null;
    globalState.enableOfflineMode = null;
    globalState.restoreOnlineMode = null;
    globalState.refreshXboardSubscription = null;
    globalState.refreshXboardNodes = null;
    super.dispose();
  }
}

class _LoginBootstrapPage extends StatelessWidget {
  const _LoginBootstrapPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(context.appLocalizations.checkingLoginStatus),
          ],
        ),
      ),
    );
  }
}
