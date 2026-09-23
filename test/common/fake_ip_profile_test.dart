import 'package:fl_clash/common/network.dart';
import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Fake-IP settings survive local persistence and reach the core',
    () async {
      SharedPreferences.setMockInitialValues({});
      const patch = PatchClashConfig(
        dns: Dns(
          fakeIpRange: '198.19.0.1/16',
          fakeIpFilter: ['+.example.org', 'printer.internal'],
        ),
      );
      const config = Config(
        themeProps: defaultThemeProps,
        overrideDns: true,
        patchClashConfig: patch,
      );
      expect(await preferences.saveConfig(config), isTrue);
      final restored = await preferences.getConfig();
      expect(restored, isNotNull);
      expect(restored!.patchClashConfig.dns.fakeIpRange, '198.19.0.1/16');
      expect(
        restored.patchClashConfig.dns.fakeIpFilter,
        patch.dns.fakeIpFilter,
      );
      expect(restored.overrideDns, isTrue);

      final output = await _profile(
        patch: restored.patchClashConfig,
        overrideDns: restored.overrideDns,
      );
      final dns = output['dns'] as YamlMap;
      expect(dns['fake-ip-range'], '198.19.0.1/16');
      expect(dns['enhanced-mode'], 'fake-ip');
      expect(dns['fake-ip-filter'], containsAll(patch.dns.fakeIpFilter));
      expect(dns['fake-ip-filter'], containsAll(localNetworkFakeIpFilters));
      expect(output['rules'], contains('MATCH,Proxy'));
      expect(
        (output['rules'] as YamlList).where(
          (rule) => rule.toString().contains('example.org'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'saving local filters does not override enabled subscription DNS',
    () async {
      final output = await _profile(
        patch: const PatchClashConfig(
          dns: Dns(
            fakeIpRange: '198.19.0.1/16',
            fakeIpFilter: ['+.local-edited.example'],
          ),
        ),
        overrideDns: false,
      );
      final dns = output['dns'] as YamlMap;
      expect(dns['fake-ip-range'], '198.18.0.1/16');
      expect(dns['fake-ip-filter'], contains('subscription.example'));
      expect(dns['fake-ip-filter'], isNot(contains('+.local-edited.example')));
      expect(output['rules'], contains('MATCH,Proxy'));
    },
  );
}

Future<YamlMap> _profile({
  required PatchClashConfig patch,
  required bool overrideDns,
}) async {
  final result = await makeRealProfileTask(
    MakeRealProfileState(
      profilesPath: '/profiles',
      profileId: 1,
      rawConfig: {
        'dns': {
          'enable': true,
          'enhanced-mode': 'fake-ip',
          'fake-ip-range': '198.18.0.1/16',
          'fake-ip-filter': ['subscription.example'],
        },
        'rules': ['MATCH,Proxy'],
      },
      realPatchConfig: patch,
      overrideDns: overrideDns,
      appendSystemDns: false,
      proxyGroups: const [],
      rules: const [],
      addedRules: const [],
      defaultUA: 'FlClash-Test',
    ),
  );
  return loadYaml(result.a) as YamlMap;
}
