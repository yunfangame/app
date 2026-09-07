import 'package:fl_clash/common/reference_delay.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final rawValue in <Object>[true, 1, '1', 'true']) {
    test(
      'accepts explicit online ${rawValue.runtimeType} status $rawValue',
      () {
        expect(
          resolveXboardNodeDisplayStatus('Node', [
            _node('Node', rawData: {'is_online': rawValue}, isOnline: false),
          ]),
          XboardNodeDisplayStatus.online,
        );
      },
    );
  }

  for (final rawValue in <Object>[false, 0, '0', 'false']) {
    test(
      'accepts explicit offline ${rawValue.runtimeType} status $rawValue',
      () {
        expect(
          resolveXboardNodeDisplayStatus('Node', [
            _node('Node', rawData: {'is_online': rawValue}, isOnline: true),
          ]),
          XboardNodeDisplayStatus.offline,
        );
      },
    );
  }

  for (final rawValue in <Object?>[null, '', 'yes', 'online', 2, -1, {}, []]) {
    test('invalid status $rawValue is unknown instead of offline', () {
      for (final isOnline in [false, true]) {
        expect(
          resolveXboardNodeDisplayStatus('Node', [
            _node('Node', rawData: {'is_online': rawValue}, isOnline: isOnline),
          ]),
          XboardNodeDisplayStatus.unknown,
        );
      }
    });
  }

  test('missing API status and cached boolean fields remain unknown', () {
    for (final isOnline in [false, true]) {
      for (final rawData in <Map<String, Object?>>[
        {},
        {'name': 'Node'},
        {'online': isOnline},
      ]) {
        expect(
          resolveXboardNodeDisplayStatus('Node', [
            _node('Node', rawData: rawData, isOnline: isOnline),
          ]),
          XboardNodeDisplayStatus.unknown,
        );
      }
    }
  });

  test('empty names and unmatched nodes remain unknown', () {
    final nodes = [
      _node('Japan', rawData: {'is_online': 1}),
    ];
    expect(
      resolveXboardNodeDisplayStatus('Missing', nodes),
      XboardNodeDisplayStatus.unknown,
    );
    expect(
      resolveXboardNodeDisplayStatus('', nodes),
      XboardNodeDisplayStatus.unknown,
    );
    expect(
      resolveXboardNodeDisplayStatus('Node', const []),
      XboardNodeDisplayStatus.unknown,
    );
  });

  test('unique normalized names accept flags and display separators', () {
    expect(
      resolveXboardNodeDisplayStatus('日本 专线 01', [
        _node('🇯🇵 日本-专线-01', rawData: {'is_online': 1}),
      ]),
      XboardNodeDisplayStatus.online,
    );
    expect(
      resolveXboardNodeDisplayStatus('us west 01', [
        _node('🇺🇸 US_West·01', rawData: {'is_online': 0}),
      ]),
      XboardNodeDisplayStatus.offline,
    );
  });

  test('an exact match wins over normalized alternatives', () {
    final nodes = [
      _node('🇯🇵 日本-专线-01', rawData: {'is_online': 1}),
      _node('日本 专线 01', rawData: {'is_online': 0}),
      _node('日本_专线_01', rawData: {'is_online': 1}),
    ];
    expect(
      resolveXboardNodeDisplayStatus('日本 专线 01', nodes),
      XboardNodeDisplayStatus.offline,
    );
  });

  test('an exact match with missing status does not borrow another status', () {
    expect(
      resolveXboardNodeDisplayStatus('日本 专线 01', [
        _node('日本-专线-01', rawData: {'is_online': 1}),
        _node('日本 专线 01', rawData: {}),
      ]),
      XboardNodeDisplayStatus.unknown,
    );
  });

  test('duplicate exact matches remain unknown even when statuses agree', () {
    for (final secondStatus in [0, 1]) {
      expect(
        resolveXboardNodeDisplayStatus('Node', [
          _node('Node', rawData: {'is_online': 1}),
          _node('Node', rawData: {'is_online': secondStatus}),
        ]),
        XboardNodeDisplayStatus.unknown,
      );
    }
  });

  test('ambiguous normalized matches remain unknown', () {
    expect(
      resolveXboardNodeDisplayStatus('日本 专线 01', [
        _node('🇯🇵 日本-专线-01', rawData: {'is_online': 1}),
        _node('日本_专线_01', rawData: {'is_online': 1}),
      ]),
      XboardNodeDisplayStatus.unknown,
    );
  });

  test('unavailable metadata never claims online or offline', () {
    for (final rawValue in [0, 1]) {
      expect(
        resolveXboardNodeDisplayStatus('Node', [
          _node('Node', rawData: {'is_online': rawValue}),
        ], statusAvailable: false),
        XboardNodeDisplayStatus.unknown,
      );
    }
  });

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
    const Locale('ru'),
  ]) {
    test('failed delay displays localized timeout in $locale', () async {
      await AppLocalizations.load(locale);
      final l10n = AppLocalizations.current;
      final expected = {
        XboardNodeDisplayStatus.online: l10n.nodeBackendOnline,
        XboardNodeDisplayStatus.offline: l10n.nodeBackendOffline,
        XboardNodeDisplayStatus.unknown: l10n.nodeStatusUnknown,
      };
      for (final entry in expected.entries) {
        expect(formatXboardNodeDisplayStatus(entry.key), entry.value);
        for (final delay in [-1, -100]) {
          final text = formatReferenceDelay(delay);
          expect(text, l10n.timeout);
          expect(text, isNot(contains('ms')));
          expect(referenceDelayMilliseconds(delay), delay);
        }
      }
      expect(formatReferenceDelay(-1), l10n.timeout);
    });

    test(
      'backend status does not alter valid or pending delay in $locale',
      () async {
        await AppLocalizations.load(locale);
        final l10n = AppLocalizations.current;
        expect(formatReferenceDelay(0), l10n.testingStatus);
        expect(formatReferenceDelay(80), l10n.referenceDelayValue(80));
        expect(formatReferenceDelay(150), l10n.referenceDelayValue(150));
        expect(formatReferenceDelay(500), l10n.referenceDelayValue(500));
      },
    );
  }
}

XboardNodeData _node(
  String name, {
  required Map<String, Object?> rawData,
  bool isOnline = false,
}) {
  return XboardNodeData(
    name: name,
    type: 'ss',
    rate: 1,
    tags: const [],
    isOnline: isOnline,
    rawData: rawData,
  );
}
