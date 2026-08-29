import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFile extends Mock implements File {}

void main() {
  group('FileInfo', () {
    late MockFile file;

    setUp(() {
      file = MockFile();
    });

    test('reads size and valid last modified time', () async {
      final lastModified = DateTime(2026, 7, 29);
      when(() => file.exists()).thenAnswer((_) async => true);
      when(() => file.length()).thenAnswer((_) async => 2048);
      when(() => file.lastModified()).thenAnswer((_) async => lastModified);

      final fileInfo = await file.getFileInfo();

      expect(fileInfo, FileInfo(size: 2048, lastModified: lastModified));
    });

    test(
      'treats positive timestamps within the epoch year as unknown',
      () async {
        when(() => file.exists()).thenAnswer((_) async => true);
        when(() => file.length()).thenAnswer((_) async => 1024);
        when(
          () => file.lastModified(),
        ).thenAnswer((_) async => DateTime(1970, 12, 31, 23, 59, 59));

        final fileInfo = await file.getFileInfo();

        expect(fileInfo, const FileInfo(size: 1024));
      },
    );

    test('keeps size when last modified time cannot be read', () async {
      when(() => file.exists()).thenAnswer((_) async => true);
      when(() => file.length()).thenAnswer((_) async => 1024);
      when(
        () => file.lastModified(),
      ).thenThrow(const FileSystemException('last modified unavailable'));

      final fileInfo = await file.getFileInfo();

      expect(fileInfo, const FileInfo(size: 1024));
    });

    test('returns null when file does not exist', () async {
      when(() => file.exists()).thenAnswer((_) async => false);

      expect(await file.getFileInfo(), isNull);
      verifyNever(() => file.length());
      verifyNever(() => file.lastModified());
    });

    testWidgets('shows unknown while preserving file size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Builder(
            builder: (context) {
              return Text(const FileInfo(size: 1024).getDesc(context));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1KB  ·  Unknown'), findsOneWidget);
    });

    testWidgets('shows relative time for valid last modified time', (
      tester,
    ) async {
      final lastModified = DateTime.now().subtract(const Duration(days: 2));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Builder(
            builder: (context) {
              return Text(
                FileInfo(
                  size: 1024,
                  lastModified: lastModified,
                ).getDesc(context),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1KB  ·  2 days ago'), findsOneWidget);
    });
  });

  group('PackagesExt', () {
    const packages = [
      Package(
        packageName: 'system.app',
        label: 'System',
        system: true,
        internet: true,
        lastUpdateTime: 1,
      ),
      Package(
        packageName: 'user.old',
        label: 'Alpha',
        system: false,
        internet: false,
        lastUpdateTime: 2,
      ),
      Package(
        packageName: 'user.new',
        label: 'Beta',
        system: false,
        internet: true,
        lastUpdateTime: 3,
      ),
    ];

    test('filters system and non-internet apps', () {
      final result = packages.getViewList(
        pinedList: [],
        sortType: AccessSortType.none,
        isFilterSystemApp: true,
        isFilterNonInternetApp: true,
      );

      expect(result.map((item) => item.packageName), ['user.new']);
    });

    test('pins selected packages before sorted packages', () {
      final result = packages.getViewList(
        pinedList: ['user.old'],
        sortType: AccessSortType.name,
        isFilterSystemApp: false,
        isFilterNonInternetApp: false,
      );

      expect(result.map((item) => item.packageName), [
        'user.old',
        'user.new',
        'system.app',
      ]);
    });
  });

  group('TrackerInfoExt', () {
    test('builds destination description and process text', () {
      final trackerInfo = TrackerInfo(
        id: '1',
        start: DateTime(2026),
        metadata: const Metadata(
          network: 'tcp',
          host: 'example.com',
          destinationIP: '1.1.1.1',
          destinationPort: '443',
          process: 'Browser',
          uid: 501,
        ),
        chains: const ['Proxy'],
        rule: 'MATCH',
        rulePayload: '',
      );

      expect(trackerInfo.desc, 'tcp://example.com/1.1.1.1:443');
      expect(trackerInfo.progressText, 'Browser(501)');
    });
  });

  group('TrafficExt', () {
    test('formats speed, description, tray title, and total speed', () {
      const traffic = Traffic(up: 1024, down: 2048);

      expect(traffic.speedText, '↑ 1KB/s   ↓ 2KB/s');
      expect(traffic.desc, '1KB ↑ 2KB ↓');
      expect(traffic.trayTitle, '1 KB/s\n2 KB/s');
      expect(traffic.speed, 3072);
    });
  });

  group('GroupsExt', () {
    test('finds group by name and resolves current selection', () {
      const groups = [
        Group(name: 'Auto', type: GroupType.URLTest, now: 'Proxy A'),
        Group(name: 'Manual', type: GroupType.Selector, now: 'Proxy B'),
      ];

      expect(
        groups.getGroup('Auto')?.getCurrentSelectedName('Proxy C'),
        'Proxy A',
      );
      expect(
        groups.getGroup('Manual')?.getCurrentSelectedName('Proxy C'),
        'Proxy C',
      );
      expect(groups.getGroup('Missing'), isNull);
    });
  });

  group('IpInfo parsers', () {
    test('parse supported response shapes', () {
      expect(
        IpInfo.fromIpInfoIoJson({
          'ip': '1.1.1.1',
          'country': 'US',
          'loc': '37.7749,-122.4194',
        }),
        const IpInfo(
          ip: '1.1.1.1',
          countryCode: 'US',
          latitude: 37.7749,
          longitude: -122.4194,
        ),
      );
      expect(
        IpInfo.fromMyIpJson({'ip': '2.2.2.2', 'cc': 'JP'}),
        const IpInfo(ip: '2.2.2.2', countryCode: 'JP'),
      );
      expect(
        IpInfo.fromIpApiCoJson({
          'ip': '3.3.3.3',
          'country_code': 'CN',
          'latitude': '31.2304',
          'longitude': '121.4737',
        }),
        const IpInfo(
          ip: '3.3.3.3',
          countryCode: 'CN',
          latitude: 31.2304,
          longitude: 121.4737,
        ),
      );
      expect(
        IpInfo.fromIpSbJson({
          'ip': '4.4.4.4',
          'country_code': 'DE',
          'latitude': 52.52,
          'longitude': 13.405,
        }),
        const IpInfo(
          ip: '4.4.4.4',
          countryCode: 'DE',
          latitude: 52.52,
          longitude: 13.405,
        ),
      );
      expect(
        IpInfo.fromIpWhoIsJson({
          'ip': '5.5.5.5',
          'country_code': 'SG',
          'latitude': 1.3521,
          'longitude': 103.8198,
        }),
        const IpInfo(
          ip: '5.5.5.5',
          countryCode: 'SG',
          latitude: 1.3521,
          longitude: 103.8198,
        ),
      );
      expect(
        IpInfo.fromIpAPIJson({
          'query': '6.6.6.6',
          'countryCode': 'AU',
          'lat': -33.8688,
          'lon': 151.2093,
        }),
        const IpInfo(
          ip: '6.6.6.6',
          countryCode: 'AU',
          latitude: -33.8688,
          longitude: 151.2093,
        ),
      );
      expect(
        IpInfo.fromIdentMeJson({
          'ip': '7.7.7.7',
          'cc': 'GB',
          'latitude': 51.5072,
          'longitude': -0.127586,
        }),
        const IpInfo(
          ip: '7.7.7.7',
          countryCode: 'GB',
          latitude: 51.5072,
          longitude: -0.127586,
        ),
      );
    });

    test('requires a complete in-range coordinate pair', () {
      expect(
        const IpInfo(
          ip: '1.1.1.1',
          countryCode: 'US',
          latitude: 90,
          longitude: -180,
        ).hasCoordinates,
        isTrue,
      );
      expect(
        const IpInfo(
          ip: '1.1.1.1',
          countryCode: 'US',
          latitude: 91,
          longitude: 0,
        ).hasCoordinates,
        isFalse,
      );
      expect(
        const IpInfo(
          ip: '1.1.1.1',
          countryCode: 'US',
          latitude: 0,
        ).hasCoordinates,
        isFalse,
      );
    });

    test('throw FormatException for unsupported response shapes', () {
      expect(
        () => IpInfo.fromIpInfoIoJson({'ip': '1.1.1.1'}),
        throwsFormatException,
      );
      expect(
        () => IpInfo.fromIpApiCoJson({'ip': '1.1.1.1'}),
        throwsFormatException,
      );
    });
  });

  group('Request.checkIp', () {
    test('prefers a coordinate response over an earlier fallback', () async {
      final adapter = _IpInfoAdapter((uri) {
        if (uri.host == 'api.myip.com') {
          return const _IpResponse(
            delay: Duration(milliseconds: 1),
            body: {'ip': '1.1.1.1', 'cc': 'US'},
          );
        }
        if (uri.host == 'ipwho.is') {
          return const _IpResponse(
            delay: Duration(milliseconds: 20),
            body: {
              'ip': '2.2.2.2',
              'country_code': 'SG',
              'latitude': 1.3521,
              'longitude': 103.8198,
            },
          );
        }
        return const _IpResponse(
          delay: Duration(milliseconds: 100),
          body: {
            'ip': '3.3.3.3',
            'query': '3.3.3.3',
            'country': 'US',
            'country_code': 'US',
            'countryCode': 'US',
            'cc': 'US',
          },
        );
      });
      final ipRequest = Request()..dio.httpClientAdapter = adapter;

      final result = await ipRequest.checkIp();

      expect(result.isSuccess, isTrue);
      expect(
        result.data,
        const IpInfo(
          ip: '2.2.2.2',
          countryCode: 'SG',
          latitude: 1.3521,
          longitude: 103.8198,
        ),
      );
      expect(adapter.requestedCount, 7);
      expect(adapter.completedCount, lessThan(7));
    });

    test('waits for every source before returning a fallback', () async {
      final adapter = _IpInfoAdapter(
        (_) => const _IpResponse(
          delay: Duration(milliseconds: 5),
          body: {
            'ip': '4.4.4.4',
            'query': '4.4.4.4',
            'country': 'CA',
            'country_code': 'CA',
            'countryCode': 'CA',
            'cc': 'CA',
          },
        ),
      );
      final ipRequest = Request()..dio.httpClientAdapter = adapter;

      final result = await ipRequest.checkIp();

      expect(result.isSuccess, isTrue);
      expect(result.data?.ip, '4.4.4.4');
      expect(result.data?.hasCoordinates, isFalse);
      expect(adapter.requestedCount, 7);
      expect(adapter.completedCount, 7);
    });

    test('preserves cancellation as an error result', () async {
      final adapter = _IpInfoAdapter(
        (_) => const _IpResponse(
          delay: Duration(seconds: 1),
          body: {'ip': '1.1.1.1', 'cc': 'US'},
        ),
      );
      final ipRequest = Request()..dio.httpClientAdapter = adapter;
      final cancelToken = CancelToken();

      final resultFuture = ipRequest.checkIp(cancelToken: cancelToken);
      await Future<void>.delayed(Duration.zero);
      cancelToken.cancel();
      final result = await resultFuture;

      expect(result.isError, isTrue);
      expect(result.message, 'cancelled');
    });
  });

  group('ResultExt', () {
    test('identifies success and error results', () {
      final success = Result.success('ok');
      final error = Result<Object>.error('failed');

      expect(success.isSuccess, isTrue);
      expect(success.isError, isFalse);
      expect(error.isSuccess, isFalse);
      expect(error.isError, isTrue);
    });
  });

  group('RuleExt', () {
    test('serializes a MATCH fallback without an empty content field', () {
      const rule = Rule(
        ruleAction: RuleAction.MATCH,
        ruleTarget: 'Manual select',
      );

      expect(rule.rawValue, 'MATCH,Manual select');
    });
  });
}

typedef _IpResponseFactory = _IpResponse Function(Uri uri);

class _IpResponse {
  const _IpResponse({required this.delay, required this.body});

  final Duration delay;
  final Map<String, Object?> body;
}

class _IpInfoAdapter implements HttpClientAdapter {
  _IpInfoAdapter(this._responseFactory);

  final _IpResponseFactory _responseFactory;

  int requestedCount = 0;
  int completedCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedCount++;
    final response = _responseFactory(options.uri);
    await Future.any<void>([
      Future<void>.delayed(response.delay),
      if (cancelFuture != null)
        cancelFuture.then<void>(
          (_) => throw DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            error: 'cancelled',
          ),
        ),
    ]);
    completedCount++;
    return ResponseBody.fromString(
      jsonEncode(response.body),
      HttpStatus.ok,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
