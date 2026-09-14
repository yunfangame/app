import 'dart:async';

import 'package:fl_clash/common/xboard_session_storage.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('remember me keeps account metadata and secrets separately', () async {
    final storage = XboardSessionStorage();

    await storage.save(
      email: 'user@example.com',
      password: 'secret-password',
      rememberMe: true,
      autoLogin: true,
      endpoint: Uri.parse('https://api.example.com/api/v1/passport/auth/login'),
      token: 'subscription-token',
      authData: 'Bearer login-token',
      isAdmin: false,
      secureSubscription: true,
    );

    final stored = await storage.load();
    final preferences = await SharedPreferences.getInstance();
    expect(stored.rememberMe, isTrue);
    expect(stored.autoLogin, isTrue);
    expect(stored.canAutoLogin, isTrue);
    expect(stored.email, 'user@example.com');
    expect(stored.password, 'secret-password');
    expect(stored.token, 'subscription-token');
    expect(stored.authData, 'Bearer login-token');
    expect(stored.secureSubscription, isTrue);
    expect(preferences.getKeys(), isNot(contains('xboard.token')));
    expect(preferences.getKeys(), isNot(contains('xboard.auth_data')));
    expect(preferences.getKeys(), isNot(contains('xboard.password')));
  });

  test('remember only restores the same account without auto login', () async {
    final storage = XboardSessionStorage();
    await storage.save(
      email: 'user@example.com',
      password: 'secret-password',
      rememberMe: true,
      autoLogin: false,
      endpoint: Uri.parse('https://api.example.com'),
      token: 'subscription-token',
      authData: 'Bearer login-token',
      isAdmin: false,
    );
    final stored = await storage.load();
    expect(stored.canAutoLogin, isFalse);
    expect(stored.canRestoreForEmail(' USER@example.com '), isTrue);
    expect(stored.canRestoreForEmail('other@example.com'), isFalse);
    expect(stored.canRestoreForEmail(''), isFalse);
    await storage.clearInvalidSession();
    expect(
      (await storage.load()).canRestoreForEmail('user@example.com'),
      isFalse,
    );
  });

  test('blank credentials cannot restore or auto login', () {
    final stored = XboardStoredSession(
      rememberMe: true,
      autoLogin: true,
      email: 'user@example.com',
      endpoint: Uri.parse('https://api.example.com'),
      token: ' ',
      authData: 'Bearer token',
    );
    expect(stored.canRestore, isFalse);
    expect(stored.canAutoLogin, isFalse);
  });

  test('macOS Debug storage avoids Keychain and persists a session', () async {
    final storage = XboardSessionStorage(useLocalDebugStorage: true);

    await storage.save(
      email: 'debug@example.com',
      password: 'debug-password',
      rememberMe: true,
      autoLogin: true,
      endpoint: Uri.parse('https://api.example.com'),
      token: 'debug-subscription-token',
      authData: 'Bearer debug-login-token',
      isAdmin: false,
      secureSubscription: true,
    );

    final stored = await storage.load();
    final preferences = await SharedPreferences.getInstance();
    expect(stored.token, 'debug-subscription-token');
    expect(stored.authData, 'Bearer debug-login-token');
    expect(stored.password, 'debug-password');
    expect(stored.secureSubscription, isTrue);
    expect(preferences.getString('xboard.token'), isNull);
    expect(preferences.getString('xboard.auth_data'), isNull);
    expect(preferences.getString('xboard.debug.token'), isNotNull);
    expect(preferences.getString('xboard.debug.auth_data'), isNotNull);
    expect(preferences.getString('xboard.debug.credentials_v2'), isNotNull);
    expect(preferences.getString('xboard.debug.password'), isNull);

    await storage.clear();
    expect(preferences.getString('xboard.debug.token'), isNull);
    expect(preferences.getString('xboard.debug.auth_data'), isNull);
    expect(preferences.getString('xboard.debug.password'), isNull);
    expect(preferences.getString('xboard.debug.credentials_v2'), isNull);
  });

  test('disabling remember me clears all persisted login data', () async {
    final storage = XboardSessionStorage();
    await storage.save(
      email: 'user@example.com',
      password: 'secret-password',
      rememberMe: true,
      autoLogin: true,
      endpoint: Uri.parse('https://api.example.com'),
      token: 'subscription-token',
      authData: 'Bearer login-token',
      isAdmin: false,
    );

    await storage.save(
      email: 'user@example.com',
      password: 'secret-password',
      rememberMe: false,
      autoLogin: false,
      endpoint: Uri.parse('https://api.example.com'),
      token: 'subscription-token',
      authData: 'Bearer login-token',
      isAdmin: false,
    );

    final stored = await storage.load();
    expect(stored.rememberMe, isFalse);
    expect(stored.autoLogin, isFalse);
    expect(stored.email, isNull);
    expect(stored.token, isNull);
    expect(stored.authData, isNull);
    expect(stored.password, isNull);
  });

  test('an invalid server session keeps remembered credentials', () async {
    final storage = XboardSessionStorage();
    await storage.save(
      email: 'user@example.com',
      password: 'secret-password',
      rememberMe: true,
      autoLogin: true,
      endpoint: Uri.parse('https://api.example.com'),
      token: 'subscription-token',
      authData: 'Bearer login-token',
      isAdmin: false,
    );

    await storage.clearInvalidSession();

    final stored = await storage.load();
    expect(stored.rememberMe, isTrue);
    expect(stored.autoLogin, isFalse);
    expect(stored.email, 'user@example.com');
    expect(stored.password, 'secret-password');
    expect(stored.token, isNull);
    expect(stored.authData, isNull);
  });

  test(
    'automatic login can be disabled without forgetting the account',
    () async {
      final storage = XboardSessionStorage();
      await storage.save(
        email: 'user@example.com',
        password: 'secret-password',
        rememberMe: true,
        autoLogin: true,
        endpoint: Uri.parse('https://api.example.com'),
        token: 'subscription-token',
        authData: 'Bearer login-token',
        isAdmin: false,
      );

      await storage.disableAutoLogin();

      final stored = await storage.load();
      expect(stored.rememberMe, isTrue);
      expect(stored.autoLogin, isFalse);
      expect(stored.email, 'user@example.com');
      expect(stored.token, 'subscription-token');
      expect(stored.authData, 'Bearer login-token');
      expect(stored.password, 'secret-password');
    },
  );

  test(
    'logout keeps remembered credentials but revokes session reuse',
    () async {
      final storage = XboardSessionStorage();
      await storage.save(
        email: 'user@example.com',
        password: 'secret-password',
        rememberMe: true,
        autoLogin: true,
        endpoint: Uri.parse('https://api.example.com'),
        token: 'subscription-token',
        authData: 'Bearer login-token',
        isAdmin: false,
      );

      final remembered = await storage.prepareForLogout();
      final stored = await storage.load();

      expect(remembered.rememberMe, isTrue);
      expect(remembered.autoLogin, isFalse);
      expect(remembered.email, 'user@example.com');
      expect(remembered.password, 'secret-password');
      expect(stored.rememberMe, isTrue);
      expect(stored.autoLogin, isFalse);
      expect(stored.email, 'user@example.com');
      expect(stored.password, 'secret-password');
      expect(stored.endpoint, isNull);
      expect(stored.token, isNull);
      expect(stored.authData, isNull);
    },
  );

  test('token login does not overwrite the remembered password', () async {
    final storage = XboardSessionStorage();
    await storage.save(
      email: 'user@example.com',
      password: ' secret password ',
      rememberMe: true,
      autoLogin: false,
      endpoint: Uri.parse('https://api.example.com'),
      token: 'subscription-token',
      authData: 'Bearer login-token',
      isAdmin: false,
    );

    await storage.save(
      email: 'user@example.com',
      password: '',
      rememberMe: true,
      autoLogin: false,
      endpoint: Uri.parse('https://api.example.com'),
      token: 'refreshed-subscription-token',
      authData: 'Bearer refreshed-login-token',
      isAdmin: false,
    );

    expect((await storage.load()).password, ' secret password ');
  });

  test('tracks the account-owned subscription profile independently', () async {
    final storage = XboardSessionStorage();
    const url = 'https://subscribe.example.com/client/account-a';

    await storage.setManagedProfileUrl(url);
    expect(await storage.loadManagedProfileUrl(), url);

    await storage.clear();
    expect(await storage.loadManagedProfileUrl(), url);

    await storage.clearManagedProfileUrl();
    expect(await storage.loadManagedProfileUrl(), isNull);
  });

  group('managed profile storage transactions', () {
    const previousUrl = 'https://previous.example/s/current-account';
    const attemptedUrl = 'https://old-api.example/s/current-account';
    const latestUrl = 'https://new-api.example/s/new-account';
    const preferenceKey = 'xboard.managed_profile_url';

    test('rejects a stale session after waiting for preferences', () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(preferenceKey, previousUrl);
      final entered = Completer<void>();
      final release = Completer<SharedPreferences>();
      var current = true;
      final storage = XboardSessionStorage(
        preferencesLoader: () {
          entered.complete();
          return release.future;
        },
      );
      final update = storage.setManagedProfileUrl(
        attemptedUrl,
        isCurrent: () => current,
      );
      final assertion = expectLater(update, throwsStateError);
      await entered.future;
      current = false;
      release.complete(preferences);
      await assertion;

      expect(preferences.getString(preferenceKey), previousUrl);
      expect(await XboardSessionStorage().loadManagedProfileUrl(), previousUrl);
    });

    for (final hasPrevious in [false, true]) {
      test(
        'rolls back a stale write before another instance can read ($hasPrevious)',
        () async {
          final preferences = await SharedPreferences.getInstance();
          if (hasPrevious) {
            await preferences.setString(preferenceKey, previousUrl);
          }
          final controlled = _ManagedProfilePreferences(preferences)
            ..pausedValue = attemptedUrl;
          var current = true;
          final storage = XboardSessionStorage(
            preferencesLoader: () async => controlled,
          );
          final update = storage.setManagedProfileUrl(
            attemptedUrl,
            isCurrent: () => current,
          );
          final assertion = expectLater(update, throwsStateError);
          await controlled.writeStarted.future;
          expect(preferences.getString(preferenceKey), attemptedUrl);
          final read = XboardSessionStorage().loadManagedProfileUrl();
          current = false;
          controlled.writeRelease.complete();
          await assertion;

          expect(await read, hasPrevious ? previousUrl : null);
          expect(
            preferences.getString(preferenceKey),
            hasPrevious ? previousUrl : null,
          );
        },
      );
    }

    test('an old instance rolls back before a new session commits', () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(preferenceKey, previousUrl);
      final controlled = _ManagedProfilePreferences(preferences)
        ..pausedValue = attemptedUrl;
      var current = true;
      final oldStorage = XboardSessionStorage(
        preferencesLoader: () async => controlled,
      );
      final oldUpdate = oldStorage.setManagedProfileUrl(
        attemptedUrl,
        isCurrent: () => current,
      );
      final assertion = expectLater(oldUpdate, throwsStateError);
      await controlled.writeStarted.future;
      current = false;
      final newUpdate = XboardSessionStorage().setManagedProfileUrl(latestUrl);
      controlled.writeRelease.complete();
      await assertion;
      await newUpdate;

      expect(await XboardSessionStorage().loadManagedProfileUrl(), latestUrl);
    });

    test(
      'a queued clear runs after an invalidated write is rolled back',
      () async {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(preferenceKey, previousUrl);
        final controlled = _ManagedProfilePreferences(preferences)
          ..pausedValue = attemptedUrl;
        var current = true;
        final storage = XboardSessionStorage(
          preferencesLoader: () async => controlled,
        );
        final update = storage.setManagedProfileUrl(
          attemptedUrl,
          isCurrent: () => current,
        );
        final assertion = expectLater(update, throwsStateError);
        await controlled.writeStarted.future;
        current = false;
        final cleared = XboardSessionStorage().clearManagedProfileUrl();
        controlled.writeRelease.complete();
        await assertion;
        await cleared;

        expect(await storage.loadManagedProfileUrl(), isNull);
      },
    );

    test(
      'a rejected write restores the old value and does not poison the queue',
      () async {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(preferenceKey, previousUrl);
        final controlled = _ManagedProfilePreferences(preferences)
          ..rejectedValue = attemptedUrl;
        final storage = XboardSessionStorage(
          preferencesLoader: () async => controlled,
        );

        await expectLater(
          storage.setManagedProfileUrl(attemptedUrl),
          throwsA(isA<XboardStorageException>()),
        );
        expect(await storage.loadManagedProfileUrl(), previousUrl);
        await XboardSessionStorage().setManagedProfileUrl(latestUrl);
        expect(await storage.loadManagedProfileUrl(), latestUrl);
      },
    );
  });

  test('offline cache preserves subscription and node metadata', () async {
    final storage = XboardSessionStorage();
    final endpoint = Uri.parse('https://api.example.com');
    final session = XboardLoginResult(
      endpoint: endpoint,
      token: 'token',
      authData: 'Bearer auth',
      isAdmin: false,
      secureSubscription: true,
      subscription: XboardSubscriptionData(
        endpoint: endpoint,
        subscribeUrl: Uri.parse('https://api.example.com/subscribe'),
        uploadBytes: 1024,
        downloadBytes: 2048,
        transferEnableBytes: 4096,
        email: 'offline@example.com',
        plan: const XboardPlanData(
          id: 7,
          name: 'Offline plan',
          transferEnableBytes: 4096,
          rawData: {},
        ),
        rawData: const {},
      ),
    );
    final verifiedAt = DateTime.utc(2026, 8, 29, 8);

    await storage.saveOfflineCache(
      session: session,
      nodes: const [
        XboardNodeData(
          id: 9,
          name: 'Hong Kong',
          type: 'vless',
          rate: 1.5,
          tags: ['HK'],
          isOnline: true,
          rawData: {},
        ),
      ],
      verifiedAt: verifiedAt,
    );
    await storage.setOfflineMode(true);

    final cache = await storage.loadOfflineCache();
    expect(await storage.loadOfflineMode(), isTrue);
    expect(cache, isNotNull);
    expect(cache!.subscription.email, 'offline@example.com');
    expect(cache.subscription.plan?.name, 'Offline plan');
    expect(cache.nodes.single.rate, 1.5);
    expect(cache.nodes.single.tags, ['HK']);
    expect(cache.secureSubscription, isTrue);
    expect(cache.toSession().secureSubscription, isTrue);
    expect(cache.isUsableAt(verifiedAt.add(const Duration(days: 2))), isTrue);
    expect(cache.isUsableAt(verifiedAt.add(const Duration(days: 4))), isFalse);

    await storage.clearOfflineCache();
    expect(await storage.loadOfflineMode(), isFalse);
    expect(await storage.loadOfflineCache(), isNull);
  });
}

class _ManagedProfilePreferences extends Fake implements SharedPreferences {
  _ManagedProfilePreferences(this.inner);

  final SharedPreferences inner;
  final writeStarted = Completer<void>();
  final writeRelease = Completer<void>();
  String? pausedValue;
  String? rejectedValue;

  @override
  String? getString(String key) => inner.getString(key);

  @override
  Future<bool> setString(String key, String value) async {
    final result = await inner.setString(key, value);
    if (value == pausedValue) {
      writeStarted.complete();
      await writeRelease.future;
    }
    return value == rejectedValue ? false : result;
  }

  @override
  Future<bool> remove(String key) => inner.remove(key);
}
