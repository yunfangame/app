import 'package:fl_clash/common/campus_network.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const domains = [
    'base.fengwo1688.cc',
    'open.fengwo1688.cc',
    'vip.fengwo1688.cc',
  ];

  test('parses operator-grouped campus hosts', () {
    final config = CampusNetworkConfig.fromRemote({
      'campusHostsByOperator': {
        'telecom': [for (final domain in domains) '114.80.8.196 $domain'],
        'unicom': [for (final domain in domains) '112.65.199.196 $domain'],
        'mobile': [for (final domain in domains) '120.233.118.84 $domain'],
      },
    });

    expect(config.hostsFor(CampusOperator.telecom), {
      for (final domain in domains) domain: '114.80.8.196',
    });
    expect(config.hostsFor(CampusOperator.unicom), {
      for (final domain in domains) domain: '112.65.199.196',
    });
    expect(config.hostsFor(CampusOperator.mobile), {
      for (final domain in domains) domain: '120.233.118.84',
    });
  });

  test('converts the existing nine-line format without overwriting routes', () {
    final config = CampusNetworkConfig.fromRemote({
      'campusHosts': [
        for (final domain in domains) ...[
          '114.80.8.196 $domain',
          '112.65.199.196 $domain',
          '120.233.118.84 $domain',
        ],
      ],
    });

    expect(
      config.hostsFor(CampusOperator.telecom)['vip.fengwo1688.cc'],
      '114.80.8.196',
    );
    expect(
      config.hostsFor(CampusOperator.unicom)['vip.fengwo1688.cc'],
      '112.65.199.196',
    );
    expect(
      config.hostsFor(CampusOperator.mobile)['vip.fengwo1688.cc'],
      '120.233.118.84',
    );
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
      campusOperator: CampusOperator.unicom,
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
}
