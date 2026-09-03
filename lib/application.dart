import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/hotkey_manager.dart';
import 'package:fl_clash/manager/manager.dart';
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
  Timer? _autoUpdateProfilesTaskTimer;
  bool _preHasVpn = false;
  bool _isOpeningRegister = false;
  bool _isOpeningForgotPassword = false;
  LoginFormPrefill? _loginPrefill;
  bool _initialRememberMe = false;
  bool _initialAutoLogin = false;
  bool _offlineAvailable = false;
  _AuthenticationBootstrap _authenticationBootstrap =
      _AuthenticationBootstrap.loading;
  final _xboardAuthService = XboardAuthService(
    subscriptionV2Client: SubscriptionV2Client(),
  );
  final _xboardSessionStorage = XboardSessionStorage(
    secretStore: createPlatformSecretStringStore(),
  );
  final _appReadyCompleter = Completer<void>();

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

  Future<void> _restoreRememberedSession() async {
    try {
      final storedSession = await _xboardSessionStorage.load();
      final offlineCache = await _xboardSessionStorage.loadOfflineCache();
      final offlineRequested = await _xboardSessionStorage.loadOfflineMode();
      final hasProfiles = ref.read(profilesProvider).isNotEmpty;
      _offlineAvailable =
          hasProfiles &&
          offlineCache != null &&
          offlineCache.isUsableAt(DateTime.now());
      if (!mounted) return;
      _loginPrefill = storedSession.email == null
          ? null
          : LoginFormPrefill(email: storedSession.email!, password: '');
      _initialRememberMe = storedSession.rememberMe;
      _initialAutoLogin = storedSession.autoLogin;
      if (offlineRequested && _offlineAvailable) {
        globalState.activateXboardSession(
          offlineCache!.toSession(),
          nodes: offlineCache.nodes,
        );
        globalState.setOfflineMode(true);
        setState(() {
          _authenticationBootstrap = _AuthenticationBootstrap.home;
        });
        return;
      }
      if (offlineRequested) {
        await _xboardSessionStorage.setOfflineMode(false);
      }
      if (!storedSession.canAutoLogin) {
        setState(() {
          _authenticationBootstrap = _AuthenticationBootstrap.login;
        });
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
        if (!mounted) return;
        globalState.activateXboardSession(session);
        globalState.setOfflineMode(false);
        await _xboardSessionStorage.setOfflineMode(false);
        await _loadXboardNodes(session, ignoreOfflineMode: true);
        await _syncSubscriptionProfile(session);
        if (!mounted) return;
        setState(() {
          _authenticationBootstrap = _AuthenticationBootstrap.home;
        });
        globalState.requestXboardAnnouncementAutoPrompt();
      } on XboardAuthException catch (error) {
        final sessionExpired =
            error.failure == XboardAuthFailure.authenticationRejected;
        if (sessionExpired) {
          await _xboardSessionStorage.clearInvalidSession();
          _initialAutoLogin = false;
        }
        if (!mounted) return;
        setState(() {
          _authenticationBootstrap = _AuthenticationBootstrap.login;
        });
        _showStartupMessage(
          sessionExpired
              ? currentAppLocalizations.loginSessionExpired
              : error.failure == XboardAuthFailure.subscriptionUnavailable
              ? currentAppLocalizations.subscriptionImportFailed
              : currentAppLocalizations.automaticLoginUnavailable,
        );
      }
    } catch (error, stackTrace) {
      commonPrint.log('restore XBoard session failed: $error, $stackTrace');
      if (!mounted) return;
      setState(() {
        _authenticationBootstrap = _AuthenticationBootstrap.login;
      });
      _showStartupMessage(currentAppLocalizations.automaticLoginUnavailable);
    }
  }

  void _showStartupMessage(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
    bool rememberMe,
    bool autoLogin,
  ) async {
    globalState.setOfflineMode(false);
    await _xboardSessionStorage.setOfflineMode(false);
    try {
      await _xboardSessionStorage.save(
        email: email,
        rememberMe: rememberMe,
        autoLogin: autoLogin,
        endpoint: session.endpoint,
        token: session.token,
        authData: session.authData,
        isAdmin: session.isAdmin,
        secureSubscription: session.secureSubscription,
      );
    } catch (error, stackTrace) {
      commonPrint.log('save XBoard session failed: $error, $stackTrace');
    }
    await _syncSubscriptionProfile(session);
    globalState.requestXboardAnnouncementAutoPrompt();
  }

  Future<void> _syncSubscriptionProfile(XboardLoginResult session) async {
    commonPrint.event(
      'subscription.profile.sync.started',
      fields: {'secure_subscription': session.secureSubscription},
    );
    try {
      await _appReadyCompleter.future;
      final planName = session.subscription.plan?.name?.trim();
      final previousUrl = await _xboardSessionStorage.loadManagedProfileUrl();
      final label = planName == null || planName.isEmpty
          ? currentAppLocalizations.brandName
          : planName;
      final secureProfile = await SubscriptionV2Client().fetchProfile(
        endpoint: session.endpoint,
        userToken: session.token,
        appVersion: globalState.packageInfo.version,
        allowTokenRegistration: !session.secureSubscription,
      );
      if (secureProfile != null) {
        await ref
            .read(profilesActionProvider.notifier)
            .syncSubscriptionProfileBytes(
              secureProfile.bytes,
              sourceId: secureProfile.sourceId,
              label: label,
              replacingUrl: previousUrl,
              removeLegacyXboardProfiles: true,
            );
        await _xboardSessionStorage.setManagedProfileUrl(
          secureProfile.sourceId,
        );
        commonPrint.event(
          'subscription.profile.sync.succeeded',
          fields: {
            'protocol': 'v2',
            'content_bytes': secureProfile.bytes.length,
          },
        );
        return;
      }
      if (session.secureSubscription) {
        throw const SubscriptionV2Exception('secure_profile_unavailable');
      }
      final legacyUrl = session.subscribeUrl;
      if (legacyUrl == null) {
        throw const SubscriptionV2Exception('legacy_subscription_unavailable');
      }
      final subscriptionUrl = legacyUrl.toString();
      await ref
          .read(profilesActionProvider.notifier)
          .syncSubscriptionProfile(
            subscriptionUrl,
            label: label,
            replacingUrl: previousUrl,
          );
      await _xboardSessionStorage.setManagedProfileUrl(subscriptionUrl);
      commonPrint.event(
        'subscription.profile.sync.succeeded',
        fields: {'protocol': 'v1'},
      );
    } catch (error, stackTrace) {
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

  Future<void> _clearRememberedSession() async {
    try {
      await _xboardSessionStorage.clear();
    } catch (error, stackTrace) {
      commonPrint.log('clear XBoard session failed: $error, $stackTrace');
    }
  }

  Future<void> _disableAutomaticLogin() async {
    try {
      await _xboardSessionStorage.disableAutoLogin();
    } catch (error, stackTrace) {
      commonPrint.log(
        'disable XBoard automatic login failed: $error, $stackTrace',
      );
    }
  }

  Future<void> _logoutXboard() async {
    commonPrint.event('auth.logout.requested');
    final activeSession = globalState.xboardSession;
    final activeSubscriptionUrl = activeSession?.subscribeUrl?.toString();
    final managedProfileUrl = await _xboardSessionStorage
        .loadManagedProfileUrl();
    final subscriptionUrls = <String>{
      ?activeSubscriptionUrl,
      ?managedProfileUrl,
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
    await _xboardSessionStorage.clearManagedProfileUrl();
    await _clearRememberedSession();
    await _xboardSessionStorage.clearOfflineCache();
    globalState.setOfflineMode(false);
    _offlineAvailable = false;
    _loginPrefill = null;
    _initialRememberMe = false;
    _initialAutoLogin = false;
    commonPrint.event('auth.logout.completed');
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
    globalState.activateXboardSession(cache.toSession(), nodes: cache.nodes);
    globalState.setOfflineMode(true);
    if (mounted) setState(() => _offlineAvailable = true);
    return true;
  }

  Future<void> _openLoginForOnlineRestore() async {
    if (!mounted) return;
    final locale = ref.read(appSettingProvider).locale;
    await globalState.navigatorKey.currentState?.pushReplacement<void, void>(
      MaterialPageRoute<void>(builder: (_) => _buildLoginPage(locale)),
    );
  }

  Future<bool> _restoreOnlineMode() async {
    final storedSession = await _xboardSessionStorage.load();
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
      await _syncSubscriptionProfile(session);
      await _xboardSessionStorage.setOfflineMode(false);
      globalState.setOfflineMode(false);
      globalState.requestXboardAnnouncementAutoPrompt();
      return true;
    } on XboardAuthException catch (error) {
      if (error.failure == XboardAuthFailure.authenticationRejected) {
        await _xboardSessionStorage.clearInvalidSession();
        await _openLoginForOnlineRestore();
        return false;
      }
      rethrow;
    }
  }

  Future<bool> _refreshXboardSubscription() async {
    if (globalState.isOfflineMode) return false;
    final activeSession = globalState.xboardSession;
    if (activeSession == null || activeSession.authData.isEmpty) return false;
    final activeRevision = globalState.xboardSessionRevision;
    const retryDelays = [
      Duration.zero,
      Duration(seconds: 1),
      Duration(seconds: 2),
    ];
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
        if (!isLastAttempt &&
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
        final nodes = globalState.xboardNodes;
        globalState.activateXboardSession(updatedSession, nodes: nodes);
        try {
          await _xboardSessionStorage.updateStoredToken(updatedSession.token);
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
        await _syncSubscriptionProfile(updatedSession);
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
      'refresh XBoard subscription after payment failed: '
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
    globalState.logoutXboard = _logoutXboard;
    globalState.enableOfflineMode = _enableOfflineMode;
    globalState.restoreOnlineMode = _restoreOnlineMode;
    globalState.refreshXboardSubscription = _refreshXboardSubscription;
    unawaited(_xboardAuthService.prepareApiConfiguration());
    unawaited(_restoreRememberedSession());
    SystemNavigator.setFrameworkHandlesBack(true);
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      if (globalState.navigatorKey.currentContext != null) {
        await globalState.attach();
        commonPrint.event(
          'app.ready',
          fields: {
            'platform': Platform.operatingSystem,
            'app_version': globalState.packageInfo.version,
            'build_number': globalState.packageInfo.buildNumber,
          },
        );
        if (!_appReadyCompleter.isCompleted) {
          _appReadyCompleter.complete();
        }
      } else {
        exit(0);
      }
      _autoUpdateProfilesTask();
      _initLink();
      app?.initShortcuts();
    });
  }

  Widget _buildLoginPage(String? locale) {
    return LoginPage(
      onLogin: _openHome,
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
          globalState.activateXboardSession(session);
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
    _autoUpdateProfilesTaskTimer = Timer(const Duration(minutes: 20), () async {
      if (!globalState.isOfflineMode) {
        await ref.read(profilesActionProvider.notifier).autoUpdateProfiles();
      }
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
            ref.read(systemActionProvider.notifier).updateLocalIp();
            final hasVpn = results.contains(ConnectivityResult.vpn);
            commonPrint.event(
              'network.connectivity.changed',
              fields: {
                'transports': results.map((item) => item.name).toList(),
                'has_vpn': hasVpn,
              },
            );
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
    linkManager.destroy();
    _autoUpdateProfilesTaskTimer?.cancel();
    globalState.logoutXboard = null;
    globalState.enableOfflineMode = null;
    globalState.restoreOnlineMode = null;
    globalState.refreshXboardSubscription = null;
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
