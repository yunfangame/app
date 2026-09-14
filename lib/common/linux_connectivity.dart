import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dbus/dbus.dart';
import 'package:nm/nm.dart';

class LinuxNetworkManagerClient extends NetworkManagerClient {
  factory LinuxNetworkManagerClient({DBusClient? bus}) =>
      LinuxNetworkManagerClient._(bus ?? DBusClient.system());

  LinuxNetworkManagerClient._(this._bus) : super(bus: _bus);

  final DBusClient _bus;

  @override
  Future<void> connect() async {
    await _bus.getId();
    await super.connect();
  }

  @override
  Future<void> close() async {
    try {
      await super.close();
    } finally {
      await _bus.close();
    }
  }
}

List<ConnectivityResult> linuxInterfaceConnectivity(
  Iterable<String> names, {
  Set<String> wireless = const {},
}) {
  final results = <ConnectivityResult>{};
  for (final name in names) {
    final normalized = name.toLowerCase();
    if (normalized == 'lo' ||
        RegExp(r'^(docker|veth|virbr|br[-0-9])').hasMatch(normalized)) {
      continue;
    }
    if (RegExp(
      r'^(tun|tap|utun|wg|ppp|tailscale|zt|flclash|clash)',
    ).hasMatch(normalized)) {
      results.add(ConnectivityResult.vpn);
    } else if (wireless.contains(name)) {
      results.add(ConnectivityResult.wifi);
    } else {
      results.add(ConnectivityResult.ethernet);
    }
  }
  return results.isEmpty ? [ConnectivityResult.none] : results.toList()
    ..sort((a, b) => a.index.compareTo(b.index));
}

Future<List<ConnectivityResult>> probeLinuxInterfaces() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    includeLinkLocal: false,
  );
  final wireless = <String>{};
  for (final interface in interfaces) {
    if (await Directory('/sys/class/net/${interface.name}/wireless').exists()) {
      wireless.add(interface.name);
    }
  }
  return linuxInterfaceConnectivity(
    interfaces.map((interface) => interface.name),
    wireless: wireless,
  );
}

class LinuxConnectivityMonitor {
  LinuxConnectivityMonitor({
    NetworkManagerClient Function()? createClient,
    Future<List<ConnectivityResult>> Function()? probeInterfaces,
    this.pollInterval = const Duration(seconds: 5),
    this.connectTimeout = const Duration(seconds: 3),
    this.onError,
  }) : createClient = createClient ?? LinuxNetworkManagerClient.new,
       probeInterfaces = probeInterfaces ?? probeLinuxInterfaces;

  final NetworkManagerClient Function() createClient;
  final Future<List<ConnectivityResult>> Function() probeInterfaces;
  final Duration pollInterval;
  final Duration connectTimeout;
  final void Function(Object error, StackTrace stack)? onError;

  Stream<List<ConnectivityResult>> get changes =>
      _watch().distinct(const ListEquality<ConnectivityResult>().equals);

  List<ConnectivityResult> _snapshot(NetworkManagerClient client) {
    if (client.connectivity == NetworkManagerConnectivityState.none) {
      return [ConnectivityResult.none];
    }
    final type = client.primaryConnectionType;
    final results = [
      if (type.contains('wireless')) ConnectivityResult.wifi,
      if (type.contains('ethernet')) ConnectivityResult.ethernet,
      if (type.contains('vpn')) ConnectivityResult.vpn,
      if (type.contains('bluetooth')) ConnectivityResult.bluetooth,
      if (type.contains('mobile')) ConnectivityResult.mobile,
    ];
    return results.isEmpty ? [ConnectivityResult.other] : results;
  }

  Stream<List<ConnectivityResult>> _watch() async* {
    final client = createClient();
    try {
      await client.connect().timeout(connectTimeout);
      yield _snapshot(client);
      await for (final properties in client.propertiesChanged) {
        if (properties.any(
          (property) => const {
            'Connectivity',
            'PrimaryConnection',
            'PrimaryConnectionType',
            'State',
          }.contains(property),
        )) {
          yield _snapshot(client);
        }
      }
    } catch (error, stack) {
      onError?.call(error, stack);
    } finally {
      try {
        await client.close();
      } catch (error, stack) {
        onError?.call(error, stack);
      }
    }
    try {
      yield await probeInterfaces();
    } catch (error, stack) {
      onError?.call(error, stack);
    }
    await for (final _ in Stream<void>.periodic(pollInterval)) {
      try {
        yield await probeInterfaces();
      } catch (error, stack) {
        onError?.call(error, stack);
      }
    }
  }
}
