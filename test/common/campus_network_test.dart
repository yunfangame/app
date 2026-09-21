import 'package:fl_clash/common/campus_network.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const domains = [
    'base.fengwo1688.cc',
    'open.fengwo1688.cc',
    'vip.fengwo1688.cc',
  ];

  test(
    'parses operator-grouped campus hosts using the remote array length',
    () {
      final config = CampusNetworkConfig.fromRemote({
        'campusHostsByOperator': {
          'telecom': [for (final domain in domains) '114.80.8.196 $domain'],
          'unicom': [for (final domain in domains) '112.65.199.196 $domain'],
        },
      });

      expect(config.hostsFor('telecom'), {
        for (final domain in domains) domain: '114.80.8.196',
      });
      expect(config.hostsFor('unicom'), {
        for (final domain in domains) domain: '112.65.199.196',
      });
      expect(config.hostsFor('mobile'), isEmpty);
      expect(availableCampusOperators(config.hostsByOperator), [
        'telecom',
        'unicom',
      ]);
    },
  );

  test('converts a legacy two-line format without inventing a third route', () {
    final config = CampusNetworkConfig.fromRemote({
      'campusHosts': [
        for (final domain in domains) ...[
          '114.80.8.196 $domain',
          '112.65.199.196 $domain',
        ],
      ],
    });

    expect(config.hostsFor('telecom')['vip.fengwo1688.cc'], '114.80.8.196');
    expect(config.hostsFor('unicom')['vip.fengwo1688.cc'], '112.65.199.196');
    expect(config.hostsFor('mobile'), isEmpty);
    expect(availableCampusOperators(config.hostsByOperator), hasLength(2));
  });

  for (final count in [1, 2, 5, 10]) {
    test('keeps all $count configured groups in remote order', () {
      final grouped = {
        for (var index = 0; index < count; index++)
          'route_${index + 1}': ['192.0.2.${index + 1} campus.example'],
      };
      final config = CampusNetworkConfig.fromRemote({
        campusNetworkConfigKey: grouped,
      });
      expect(availableCampusOperators(config.hostsByOperator), grouped.keys);
      expect(config.hostsFor('route_$count'), {
        'campus.example': '192.0.2.$count',
      });
    });
  }

  test('grouped count overrides a stale larger legacy array', () {
    final config = CampusNetworkConfig.fromRemote({
      campusNetworkConfigKey: {
        'only_line': ['192.0.2.1 campus.example'],
      },
      legacyCampusNetworkConfigKey: [
        '192.0.2.1 campus.example',
        '192.0.2.2 campus.example',
        '192.0.2.3 campus.example',
      ],
    });
    expect(availableCampusOperators(config.hostsByOperator), ['only_line']);
  });

  test('empty groups clear all routes despite a stale legacy array', () {
    final config = CampusNetworkConfig.fromRemote({
      campusNetworkConfigKey: <String, Object?>{},
      legacyCampusNetworkConfigKey: ['192.0.2.1 campus.example'],
    });
    expect(config.hostsByOperator, isEmpty);
    expect(resolveCampusOperator('telecom', config.hostsByOperator), '');
  });

  test('invalid grouped config cannot fall back to stale legacy routes', () {
    for (final grouped in [
      null,
      [],
      {
        'broken': ['bad host'],
      },
    ]) {
      expect(
        () => CampusNetworkConfig.fromRemote({
          campusNetworkConfigKey: grouped,
          legacyCampusNetworkConfigKey: ['192.0.2.1 campus.example'],
        }),
        throwsFormatException,
      );
    }
  });

  test(
    'supports more than three legacy alternatives without deduplication',
    () {
      final config = CampusNetworkConfig.fromRemote({
        legacyCampusNetworkConfigKey: [
          for (final domain in domains)
            for (var index = 0; index < 5; index++) '192.0.2.1 $domain',
        ],
      });
      expect(availableCampusOperators(config.hostsByOperator), hasLength(5));
      expect(config.hostsFor('line_5'), {
        for (final domain in domains) domain: '192.0.2.1',
      });
    },
  );

  test('applies an arbitrary selected group to Core hosts and DNS', () {
    const settings = AppSettingProps(
      campusNetworkEnabled: true,
      campusOperator: 'route_5',
      campusHostsByOperator: {
        'route_5': {'campus.example': '192.0.2.5'},
      },
    );
    final applied = applyCampusNetworkConfig(
      const PatchClashConfig(),
      settings,
    );
    expect(applied.hosts['campus.example'], '192.0.2.5');
    expect(applied.dns.useHosts, isTrue);
    expect(hasActiveCampusNetworkConfig(settings), isTrue);
  });

  test('rejects incomplete or invalid campus hosts', () {
    expect(
      () => CampusNetworkConfig.fromRemote({
        'campusHostsByOperator': {
          'telecom': ['999.80.8.196 base.fengwo1688.cc'],
        },
      }),
      throwsFormatException,
    );
  });

  test('merges active hosts without changing saved patch hosts', () {
    const patch = PatchClashConfig(hosts: {'custom.example.com': '192.0.2.1'});
    const settings = AppSettingProps(
      campusNetworkEnabled: true,
      campusOperator: 'unicom',
      campusHostsByOperator: {
        'unicom': {'base.fengwo1688.cc': '112.65.199.196'},
      },
    );

    final applied = applyCampusNetworkConfig(patch, settings);

    expect(applied.hosts, {
      'custom.example.com': '192.0.2.1',
      'base.fengwo1688.cc': '112.65.199.196',
    });
    expect(applied.dns.enable, isTrue);
    expect(applied.dns.useHosts, isTrue);
    expect(patch.hosts, {'custom.example.com': '192.0.2.1'});
  });

  test('leaves patch config unchanged while campus mode is disabled', () {
    const patch = PatchClashConfig(hosts: {'custom.example.com': '192.0.2.1'});
    const settings = AppSettingProps(
      campusHostsByOperator: {
        'telecom': {'base.fengwo1688.cc': '114.80.8.196'},
      },
    );

    expect(applyCampusNetworkConfig(patch, settings), same(patch));
  });

  test('recognizes a usable two-line cached campus configuration', () {
    expect(
      hasCompleteCampusNetworkConfig({
        'telecom': {'base.fengwo1688.cc': '192.0.2.1'},
        'unicom': {'base.fengwo1688.cc': '192.0.2.2'},
      }),
      isTrue,
    );
    expect(hasCompleteCampusNetworkConfig({}), isFalse);
  });

  test(
    'falls back to the first available line when a saved line is removed',
    () {
      final hosts = {
        'telecom': {'base.fengwo1688.cc': '192.0.2.1'},
        'unicom': {'base.fengwo1688.cc': '192.0.2.2'},
      };

      expect(resolveCampusOperator('mobile', hosts), 'telecom');
      expect(resolveCampusOperator('unicom', hosts), 'unicom');
    },
  );
}
