import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dbus/dbus.dart';
import 'package:fl_clash/common/linux_connectivity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nm/nm.dart';

class _Client extends Mock implements NetworkManagerClient {}

void main() {
  test('missing real system bus falls back without detached errors', () async {
    final directory = await Directory.systemTemp.createTemp('linux-bus-test-');
    addTearDown(directory.delete);
    final errors = <Object>[];
    final monitor = LinuxConnectivityMonitor(
      createClient: () => LinuxNetworkManagerClient(
        bus: DBusClient(
          DBusAddress('unix:path=${directory.path}/missing.sock'),
        ),
      ),
      probeInterfaces: () async => [ConnectivityResult.ethernet],
      onError: (error, _) => errors.add(error),
    );
    expect(await monitor.changes.first, [ConnectivityResult.ethernet]);
    expect(errors, [isA<SocketException>()]);
  });

  test('cancelling fallback does not wait for the next poll', () async {
    final client = _Client();
    when(client.connect).thenThrow(StateError('missing'));
    when(client.close).thenAnswer((_) async {});
    final monitor = LinuxConnectivityMonitor(
      createClient: () => client,
      pollInterval: const Duration(hours: 1),
      probeInterfaces: () async => [ConnectivityResult.ethernet],
    );
    expect(
      await monitor.changes
          .take(1)
          .toList()
          .timeout(const Duration(seconds: 1)),
      [
        [ConnectivityResult.ethernet],
      ],
    );
  });

  test('interface fallback excludes loopback and container bridges', () {
    expect(
      linuxInterfaceConnectivity([
        'lo',
        'docker0',
        'veth123',
        'virbr0',
        'br-ab',
      ]),
      [ConnectivityResult.none],
    );
    expect(linuxInterfaceConnectivity(['tun0', 'wg0']), [
      ConnectivityResult.vpn,
    ]);
    expect(
      linuxInterfaceConnectivity(['wlan0', 'tun0'], wireless: {'wlan0'}),
      containsAll([ConnectivityResult.wifi, ConnectivityResult.vpn]),
    );
    expect(linuxInterfaceConnectivity(['eth0']), [ConnectivityResult.ethernet]);
  });

  test(
    'missing NetworkManager closes its client and polls interfaces',
    () async {
      final client = _Client();
      when(client.connect).thenThrow(StateError('NetworkManager unavailable'));
      when(client.close).thenAnswer((_) async {});
      final errors = <Object>[];
      final monitor = LinuxConnectivityMonitor(
        createClient: () => client,
        probeInterfaces: () async => [ConnectivityResult.ethernet],
        onError: (error, _) => errors.add(error),
      );
      expect(await monitor.changes.first, [ConnectivityResult.ethernet]);
      expect(errors, hasLength(1));
      verify(client.close).called(1);
    },
  );

  test(
    'NetworkManager changes are observed and cancellation closes it',
    () async {
      final client = _Client();
      final properties = StreamController<List<String>>();
      addTearDown(properties.close);
      var type = 'ethernet';
      when(client.connect).thenAnswer((_) async {});
      when(client.close).thenAnswer((_) async {});
      when(
        () => client.connectivity,
      ).thenReturn(NetworkManagerConnectivityState.full);
      when(() => client.primaryConnectionType).thenAnswer((_) => type);
      when(() => client.propertiesChanged).thenAnswer((_) => properties.stream);
      final values = StreamIterator(
        LinuxConnectivityMonitor(createClient: () => client).changes,
      );
      expect(await values.moveNext(), isTrue);
      expect(values.current, [ConnectivityResult.ethernet]);
      type = 'wireless';
      properties.add(['PrimaryConnection']);
      expect(await values.moveNext(), isTrue);
      expect(values.current, [ConnectivityResult.wifi]);
      await values.cancel();
      verify(client.close).called(1);
    },
  );

  test('D-Bus stream failure falls back without an unhandled error', () async {
    final client = _Client();
    when(client.connect).thenAnswer((_) async {});
    when(client.close).thenAnswer((_) async {});
    when(
      () => client.connectivity,
    ).thenReturn(NetworkManagerConnectivityState.none);
    when(
      () => client.propertiesChanged,
    ).thenAnswer((_) => Stream.error(StateError('bus gone')));
    final monitor = LinuxConnectivityMonitor(
      createClient: () => client,
      probeInterfaces: () async => [ConnectivityResult.ethernet],
    );
    expect(await monitor.changes.take(2).toList(), [
      [ConnectivityResult.none],
      [ConnectivityResult.ethernet],
    ]);
    verify(client.close).called(1);
  });

  test('failed fallback probes do not invent an offline event', () async {
    final client = _Client();
    when(client.connect).thenThrow(StateError('missing'));
    when(client.close).thenAnswer((_) async {});
    var attempts = 0;
    final monitor = LinuxConnectivityMonitor(
      createClient: () => client,
      pollInterval: Duration.zero,
      probeInterfaces: () async {
        if (++attempts == 1) throw StateError('probe failed');
        return [ConnectivityResult.ethernet];
      },
    );
    expect(await monitor.changes.first, [ConnectivityResult.ethernet]);
    expect(attempts, 2);
  });

  test('stalled NetworkManager connection times out into fallback', () async {
    final client = _Client();
    when(client.connect).thenAnswer((_) => Completer<void>().future);
    when(client.close).thenAnswer((_) async {});
    final monitor = LinuxConnectivityMonitor(
      createClient: () => client,
      connectTimeout: const Duration(milliseconds: 5),
      probeInterfaces: () async => [ConnectivityResult.ethernet],
    );
    expect(await monitor.changes.first, [ConnectivityResult.ethernet]);
    verify(client.close).called(1);
  });
}
