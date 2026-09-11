import 'package:fl_clash/common/system_dns.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePort implements SystemDnsPort {
  _FakePort({List<String>? servers}) : servers = servers ?? ['1.1.1.1'];

  String? service = 'Wi-Fi';
  List<String> servers;
  bool writeSucceeds = true;
  Duration delay = Duration.zero;
  int inFlight = 0;
  int maxInFlight = 0;
  final List<List<String>> writes = [];
  final List<String> writtenServices = [];

  @override
  Future<String?> resolveDefaultService() => _guard(() async => service);

  @override
  Future<List<String>?> readDnsServers(String service) =>
      _guard(() async => List.of(servers));

  @override
  Future<bool> writeDnsServers(String service, List<String> servers) =>
      _guard(() async {
        if (!writeSucceeds) {
          return false;
        }
        writtenServices.add(service);
        writes.add(List.of(servers));
        if (service == this.service) {
          this.servers = List.of(servers);
        }
        return true;
      });

  Future<T> _guard<T>(Future<T> Function() body) async {
    inFlight++;
    maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
    try {
      if (delay > Duration.zero) {
        await Future.delayed(delay);
      }
      return await body();
    } finally {
      inFlight--;
    }
  }
}

class _FakeStore implements SystemDnsStore {
  _FakeStore([this.record]);

  SystemDnsRecord? record;

  @override
  Future<SystemDnsRecord?> read() async => record;

  @override
  Future<void> write(SystemDnsRecord record) async {
    this.record = record;
  }

  @override
  Future<void> clear() async {
    record = null;
  }
}

SystemDnsCoordinator _coordinator(_FakePort port, _FakeStore store) {
  return SystemDnsCoordinator(
    port: port,
    store: store,
    fallbackDns: '223.5.5.5',
  );
}

void main() {
  test('appends the fallback resolver and restores original DNS', () async {
    final port = _FakePort(servers: ['1.1.1.1']);
    final store = _FakeStore();
    final coordinator = _coordinator(port, store);

    await coordinator.sync(true);
    await coordinator.sync(false);

    expect(port.writes, [
      ['1.1.1.1', '223.5.5.5'],
      ['1.1.1.1'],
    ]);
    expect(store.record, isNull);
  });

  test('restores an empty server list to DHCP', () async {
    final port = _FakePort(servers: []);
    final coordinator = _coordinator(port, _FakeStore());

    await coordinator.sync(true);
    await coordinator.sync(false);

    expect(port.writes, [
      ['223.5.5.5'],
      <String>[],
    ]);
  });

  test('restores a record left by a previous run', () async {
    final port = _FakePort(servers: ['1.1.1.1', '223.5.5.5']);
    final store = _FakeStore(
      const SystemDnsRecord(service: 'Wi-Fi', servers: ['1.1.1.1']),
    );
    final coordinator = _coordinator(port, store);

    await coordinator.sync(false);

    expect(port.writes, [
      ['1.1.1.1'],
    ]);
    expect(store.record, isNull);
  });

  test('moves the patch when the default route changes', () async {
    final port = _FakePort(servers: ['1.1.1.1']);
    final store = _FakeStore();
    final coordinator = _coordinator(port, store);

    await coordinator.sync(true);
    port.service = 'Thunderbolt Bridge';
    port.servers = ['8.8.8.8'];
    await coordinator.resync();

    expect(port.writtenServices, ['Wi-Fi', 'Wi-Fi', 'Thunderbolt Bridge']);
    expect(store.record?.service, 'Thunderbolt Bridge');
    expect(store.record?.servers, ['8.8.8.8']);
  });

  test('keeps a failed restore for a later retry', () async {
    final port = _FakePort(servers: ['1.1.1.1']);
    final store = _FakeStore();
    final coordinator = _coordinator(port, store);

    await coordinator.sync(true);
    port.writeSucceeds = false;
    await coordinator.sync(false);
    expect(store.record, isNotNull);

    port.writeSucceeds = true;
    await coordinator.resync();
    expect(store.record, isNull);
    expect(port.writes.last, ['1.1.1.1']);
  });

  test('serializes overlapping requests onto the latest intent', () async {
    final port = _FakePort(servers: ['1.1.1.1'])
      ..delay = const Duration(milliseconds: 5);
    final store = _FakeStore();
    final coordinator = _coordinator(port, store);

    final first = coordinator.sync(true);
    final second = coordinator.sync(false);
    final third = coordinator.sync(true);
    await Future.wait([first, second, third]);

    expect(port.maxInFlight, 1);
    expect(port.writes.last, ['1.1.1.1', '223.5.5.5']);
    expect(store.record?.servers, ['1.1.1.1']);
  });

  test('shutdown restores DNS and ignores later requests', () async {
    final port = _FakePort(servers: ['1.1.1.1']);
    final store = _FakeStore();
    final coordinator = _coordinator(port, store);

    await coordinator.sync(true);
    await coordinator.shutdown();
    await coordinator.sync(true);
    await coordinator.resync();

    expect(port.writes, [
      ['1.1.1.1', '223.5.5.5'],
      ['1.1.1.1'],
    ]);
    expect(store.record, isNull);
  });

  test('decodes only a well formed record', () {
    expect(
      SystemDnsRecord.fromJson({
        'service': 'Wi-Fi',
        'servers': ['1.1.1.1', 2],
      }),
      const SystemDnsRecord(service: 'Wi-Fi', servers: ['1.1.1.1']),
    );
    expect(SystemDnsRecord.fromJson({'service': '', 'servers': []}), isNull);
    expect(SystemDnsRecord.fromJson({'service': 'Wi-Fi'}), isNull);
    expect(SystemDnsRecord.fromJson('Wi-Fi'), isNull);
  });
}
