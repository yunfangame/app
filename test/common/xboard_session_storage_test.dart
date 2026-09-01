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
    expect(stored.token, 'subscription-token');
    expect(stored.authData, 'Bearer login-token');
    expect(stored.secureSubscription, isTrue);
    expect(preferences.getKeys(), isNot(contains('xboard.token')));
    expect(preferences.getKeys(), isNot(contains('xboard.auth_data')));
  });

  test('macOS Debug storage avoids Keychain and persists a session', () async {
    final storage = XboardSessionStorage(useLocalDebugStorage: true);

    await storage.save(
      email: 'debug@example.com',
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
    expect(stored.secureSubscription, isTrue);
    expect(preferences.getString('xboard.token'), isNull);
    expect(preferences.getString('xboard.auth_data'), isNull);
    expect(preferences.getString('xboard.debug.token'), isNotNull);
    expect(preferences.getString('xboard.debug.auth_data'), isNotNull);

    await storage.clear();
    expect(preferences.getString('xboard.debug.token'), isNull);
    expect(preferences.getString('xboard.debug.auth_data'), isNull);
  });

  test('disabling remember me clears all persisted login data', () async {
    final storage = XboardSessionStorage();
    await storage.save(
      email: 'user@example.com',
      rememberMe: true,
      autoLogin: true,
      endpoint: Uri.parse('https://api.example.com'),
      token: 'subscription-token',
      authData: 'Bearer login-token',
      isAdmin: false,
    );

    await storage.save(
      email: 'user@example.com',
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
  });

  test('an invalid server session keeps the remembered email only', () async {
    final storage = XboardSessionStorage();
    await storage.save(
      email: 'user@example.com',
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
    expect(stored.token, isNull);
    expect(stored.authData, isNull);
  });

  test(
    'automatic login can be disabled without forgetting the account',
    () async {
      final storage = XboardSessionStorage();
      await storage.save(
        email: 'user@example.com',
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
    },
  );

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
