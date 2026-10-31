import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/function.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('AuthorizedTunEnable provider', () {
    test('default is none', () {
      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.none,
      );
    });

    test('can store authorized and unauthorized results', () {
      final notifier = container.read(authorizedTunEnableProvider.notifier);
      notifier.update((_) => TunAuthorizationState.authorized);
      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.authorized,
      );
      notifier.update((_) => TunAuthorizationState.unauthorized);
      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.unauthorized,
      );
    });
  });

  group('Packages provider', () {
    test('default is empty list', () {
      expect(container.read(packagesProvider), isEmpty);
    });

    test('can update state', () {
      const pkg = Package(
        packageName: 'test.app',
        label: 'Test App',
        system: false,
        internet: true,
        lastUpdateTime: 0,
      );
      container.read(packagesProvider.notifier).update((_) => [pkg]);
      expect(container.read(packagesProvider).length, 1);
      expect(container.read(packagesProvider).first.packageName, 'test.app');
    });
  });

  group('Providers provider', () {
    test('setProvider replaces provider with matching name', () {
      final oldProvider = ExternalProvider(
        name: 'Proxy',
        type: 'Proxy',
        count: 1,
        vehicleType: 'HTTP',
        updateAt: DateTime(2026),
      );
      final newProvider = oldProvider.copyWith(count: 2);
      container.read(providersProvider.notifier).update((_) => [oldProvider]);

      container.read(providersProvider.notifier).setProvider(newProvider);

      expect(container.read(providersProvider).single.count, 2);
    });

    test('setProvider ignores null and missing provider names', () {
      final provider = ExternalProvider(
        name: 'Proxy',
        type: 'Proxy',
        count: 1,
        vehicleType: 'HTTP',
        updateAt: DateTime(2026),
      );
      container.read(providersProvider.notifier).update((_) => [provider]);

      container.read(providersProvider.notifier).setProvider(null);
      container
          .read(providersProvider.notifier)
          .setProvider(provider.copyWith(name: 'Other', count: 9));

      expect(container.read(providersProvider).single, provider);
    });
  });

  group('SystemBrightness provider', () {
    test('default is dark', () {
      expect(container.read(systemBrightnessProvider), Brightness.dark);
    });

    test('can update to light', () {
      container
          .read(systemBrightnessProvider.notifier)
          .update((_) => Brightness.light);
      expect(container.read(systemBrightnessProvider), Brightness.light);
    });
  });

  group('LocalIp provider', () {
    test('default is null', () {
      expect(container.read(localIpProvider), null);
    });

    test('can set IP', () {
      container.read(localIpProvider.notifier).update((_) => '192.168.1.1');
      expect(container.read(localIpProvider), '192.168.1.1');
    });
  });

  group('RunTime provider', () {
    test('default is null', () {
      expect(container.read(runTimeProvider), null);
    });

    test('can set runtime', () {
      container.read(runTimeProvider.notifier).update((_) => 3600);
      expect(container.read(runTimeProvider), 3600);
    });
  });

  group('ViewSize provider', () {
    test('default is zero', () {
      expect(container.read(viewSizeProvider), Size.zero);
    });

    test('can update size', () {
      container
          .read(viewSizeProvider.notifier)
          .update((_) => const Size(800, 600));
      final value = container.read(viewSizeProvider);
      expect(value.width, 800);
      expect(value.height, 600);
    });
  });

  group('SideWidth provider', () {
    test('default is 0', () {
      expect(container.read(sideWidthProvider), 0.0);
    });

    test('can update side width', () {
      container.read(sideWidthProvider.notifier).update((_) => 300.0);
      expect(container.read(sideWidthProvider), 300.0);
    });
  });

  group('viewWidth provider (derived)', () {
    test('derives from viewSize width', () {
      container
          .read(viewSizeProvider.notifier)
          .update((_) => const Size(800, 600));
      expect(container.read(viewWidthProvider), 800);
    });
  });

  group('viewHeight provider (derived)', () {
    test('derives from viewSize height', () {
      container
          .read(viewSizeProvider.notifier)
          .update((_) => const Size(800, 600));
      expect(container.read(viewHeightProvider), 600);
    });
  });

  group('Init provider', () {
    test('default is false', () {
      expect(container.read(initProvider), false);
    });

    test('can update to true', () {
      container.read(initProvider.notifier).update((_) => true);
      expect(container.read(initProvider), true);
    });
  });

  group('CurrentPageLabel provider', () {
    test('default is dashboard', () {
      expect(container.read(currentPageLabelProvider), PageLabel.dashboard);
    });

    test('toPage changes page', () {
      container
          .read(currentPageLabelProvider.notifier)
          .toPage(PageLabel.proxies);
      expect(container.read(currentPageLabelProvider), PageLabel.proxies);
    });

    test('toProfiles changes page', () {
      container.read(currentPageLabelProvider.notifier).toProfiles();
      expect(container.read(currentPageLabelProvider), PageLabel.profiles);
    });
  });

  group('SortNum provider', () {
    test('default is 0', () {
      expect(container.read(sortNumProvider), 0);
    });

    test('can update', () {
      container.read(sortNumProvider.notifier).update((_) => 5);
      expect(container.read(sortNumProvider), 5);
    });
  });

  group('Version provider', () {
    test('default is 0', () {
      expect(container.read(versionProvider), 0);
    });

    test('can set version', () {
      container.read(versionProvider.notifier).update((_) => 3);
      expect(container.read(versionProvider), 3);
    });
  });

  group('Groups provider', () {
    test('default is empty', () {
      expect(container.read(groupsProvider), isEmpty);
    });

    test('can set groups', () {
      final groups = [
        const Group(name: 'G1', type: GroupType.Selector, now: 'auto'),
      ];
      container.read(groupsProvider.notifier).update((_) => groups);
      expect(container.read(groupsProvider).length, 1);
      expect(container.read(groupsProvider).first.name, 'G1');
    });
  });

  group('TotalTraffic provider', () {
    test('default is empty Traffic', () {
      final t = container.read(totalTrafficProvider);
      expect(t.up, 0);
      expect(t.down, 0);
    });
  });

  group('CheckIpNum provider', () {
    test('default is 0', () {
      expect(container.read(checkIpNumProvider), 0);
    });

    test('increment returns previous value and updates state', () {
      final value = container.read(checkIpNumProvider.notifier).add();

      expect(value, 0);
      expect(container.read(checkIpNumProvider), 1);
    });
  });

  group('SortNum provider', () {
    test('increment returns previous value and updates state', () {
      final value = container.read(sortNumProvider.notifier).add();

      expect(value, 0);
      expect(container.read(sortNumProvider), 1);
    });
  });

  group('DelayDataSource provider', () {
    test('sets delay by url and proxy name', () {
      container
          .read(delayDataSourceProvider.notifier)
          .setDelay(
            const Delay(name: 'Proxy', url: 'https://test.example', value: 120),
          );

      expect(container.read(delayDataSourceProvider), {
        'https://test.example': {'Proxy': 120},
      });
    });

    test('keeps same state instance when delay value is unchanged', () {
      final notifier = container.read(delayDataSourceProvider.notifier);
      const delay = Delay(name: 'Proxy', url: 'https://test.example', value: 1);
      notifier.setDelay(delay);
      final state = container.read(delayDataSourceProvider);

      notifier.setDelay(delay);

      expect(identical(container.read(delayDataSourceProvider), state), isTrue);
    });
  });

  group('ConnectionDelayDataSource provider', () {
    test('stores actual connection delay independently', () {
      container
          .read(connectionDelayDataSourceProvider.notifier)
          .setDelay(
            const Delay(name: 'Proxy', url: 'https://test.example', value: 220),
          );

      expect(container.read(connectionDelayDataSourceProvider), {
        'https://test.example': {'Proxy': 220},
      });
      expect(container.read(delayDataSourceProvider), isEmpty);
    });
  });

  group('Loading provider', () {
    test('stop without start sets loading false immediately', () async {
      final notifier = container.read(
        loadingProvider(LoadingTag.profiles).notifier,
      );

      await notifier.stop();

      expect(container.read(loadingProvider(LoadingTag.profiles)), false);
    });

    test('stop keeps loading visible for minimum duration', () async {
      final notifier = container.read(
        loadingProvider(LoadingTag.profiles).notifier,
      );

      notifier.start();
      await notifier.stop();

      expect(container.read(loadingProvider(LoadingTag.profiles)), true);

      await Future.delayed(const Duration(milliseconds: 1100));

      expect(container.read(loadingProvider(LoadingTag.profiles)), false);
    });
  });

  group('CoreStatus provider', () {
    test('default is disconnected', () {
      expect(container.read(coreStatusProvider), CoreStatus.disconnected);
    });
  });

  group('NetworkDetection provider', () {
    late HttpClientAdapter originalAdapter;

    setUp(() {
      originalAdapter = request.dio.httpClientAdapter;
    });

    tearDown(() {
      request.dio.httpClientAdapter = originalAdapter;
    });

    test(
      'ignores a canceled stale check after a newer check succeeds',
      () async {
        final adapter = _ControlledIpAdapter();
        request.dio.httpClientAdapter = adapter;
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => true),
            runTimeProvider.overrideWithBuild((_, _) => 1),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(() => debouncer.cancel(FunctionTag.checkIp));
        final success = Completer<void>();
        final subscription = container.listen(networkDetectionProvider, (
          _,
          next,
        ) {
          if (next.ipInfo?.ip == '2.2.2.2' &&
              !next.isLoading &&
              !success.isCompleted) {
            success.complete();
          }
        });
        addTearDown(subscription.close);
        final notifier = container.read(networkDetectionProvider.notifier);
        notifier.startCheck();
        final old = await adapter.firstStarted.future.timeout(
          const Duration(seconds: 10),
        );

        notifier.startCheck();
        final newer = await adapter.secondStarted.future.timeout(
          const Duration(seconds: 10),
        );
        await old.cancellationObserved.future.timeout(
          const Duration(seconds: 10),
        );
        expect(old.token.isCancelled, isTrue);
        newer.succeed();
        await success.future.timeout(const Duration(seconds: 10));

        expect(container.read(networkDetectionProvider).ipInfo?.ip, '2.2.2.2');
        expect(container.read(networkDetectionProvider).isLoading, false);

        old.finishCancelled();
        await Future.wait(
          old.responses.map(
            (response) => response.future.then<void>(
              (_) {},
              onError: (Object _, StackTrace _) {},
            ),
          ),
        ).timeout(const Duration(seconds: 10));

        expect(container.read(networkDetectionProvider).ipInfo?.ip, '2.2.2.2');
        expect(container.read(networkDetectionProvider).isLoading, false);
      },
    );

    test('retains a disconnected lookup as the origin location', () async {
      request.dio.httpClientAdapter = _StaticIpAdapter();
      final container = ProviderContainer(
        overrides: [
          initProvider.overrideWithBuild((_, _) => true),
          runTimeProvider.overrideWithBuild((_, _) => null),
        ],
      );
      addTearDown(container.dispose);

      container.read(networkDetectionProvider.notifier).startCheck();
      await Future.delayed(commonDuration + const Duration(milliseconds: 120));

      final state = container.read(networkDetectionProvider);
      expect(state.ipInfo?.countryCode, 'CN');
      expect(state.originIpInfo?.countryCode, 'CN');
      expect(state.originIpInfo?.latitude, closeTo(39.9042, 0.0001));
    });
  });
}

class _StaticIpAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"ip":"198.51.100.8","country_code":"CN",'
      '"latitude":39.9042,"longitude":116.4074}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ControlledIpAdapter implements HttpClientAdapter {
  final attempts = <_IpAttempt>[];
  final firstStarted = Completer<_IpAttempt>();
  final secondStarted = Completer<_IpAttempt>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final token = options.cancelToken!;
    final matches = attempts.where(
      (attempt) => identical(attempt.token, token),
    );
    final attempt = matches.isEmpty ? _IpAttempt(token) : matches.single;
    if (matches.isEmpty) {
      attempts.add(attempt);
      if (attempts.length == 1) firstStarted.complete(attempt);
      if (attempts.length == 2) secondStarted.complete(attempt);
    }
    return attempt.add(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

class _IpAttempt {
  _IpAttempt(this.token);

  final CancelToken token;
  final cancellationObserved = Completer<void>();
  final requests = <RequestOptions>[];
  final responses = <Completer<ResponseBody>>[];

  Future<ResponseBody> add(RequestOptions options, Future<void>? cancelFuture) {
    requests.add(options);
    final response = Completer<ResponseBody>();
    responses.add(response);
    cancelFuture?.then((_) {
      if (!cancellationObserved.isCompleted) cancellationObserved.complete();
    });
    return response.future;
  }

  void succeed() {
    final payload = jsonEncode({
      'ip': '2.2.2.2',
      'query': '2.2.2.2',
      'country_code': 'US',
      'countryCode': 'US',
      'country': 'US',
      'cc': 'US',
      'latitude': 37.0,
      'longitude': -122.0,
      'lat': 37.0,
      'lon': -122.0,
      'loc': '37.0,-122.0',
    });
    for (final response in responses) {
      response.complete(
        ResponseBody.fromString(
          payload,
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      );
    }
  }

  void finishCancelled() {
    for (var index = 0; index < responses.length; index++) {
      responses[index].completeError(
        DioException(
          requestOptions: requests[index],
          type: DioExceptionType.cancel,
          error: 'controlled old cancellation',
        ),
      );
    }
  }
}
