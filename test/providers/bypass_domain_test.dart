import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _BypassSetup extends SetupAction {
  int applies = 0;

  @override
  void requestBypassProfileApply() => applies++;
}

void main() {
  test(
    'scoped bypass changes reapply profile and remove DNS overrides on mode changes',
    () {
      final container = ProviderContainer(
        overrides: [setupActionProvider.overrideWith(_BypassSetup.new)],
      );
      addTearDown(container.dispose);
      final setup =
          container.read(setupActionProvider.notifier) as _BypassSetup;
      final network = container.read(networkSettingProvider.notifier);
      network.update(
        (state) => state.copyWith(bypassDomain: ['oa.corp.example']),
      );
      expect(setup.applies, 0);
      network.update((state) => state.copyWith(bypassDomainRouting: true));
      expect(setup.applies, 1);
      network.update((state) => state.copyWith(bypassDomainDns: '10.0.0.53'));
      expect(setup.applies, 2);
      network.update(
        (state) => state.copyWith(bypassDomain: ['*.corp.example']),
      );
      expect(setup.applies, 3);
      network.update((state) => state.copyWith(systemProxy: false));
      expect(setup.applies, 3);
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: Mode.global));
      expect(setup.applies, 4);
      network.update(
        (state) => state.copyWith(bypassDomain: ['new.corp.example']),
      );
      expect(setup.applies, 4);
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: Mode.rule));
      expect(setup.applies, 5);
      network.update((state) => state.copyWith(bypassDomainRouting: false));
      expect(setup.applies, 6);
      network.update((state) => state.copyWith(bypassDomainDns: 'system://'));
      expect(setup.applies, 6);
    },
  );
}
