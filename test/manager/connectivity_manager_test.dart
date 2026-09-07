import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/manager/connectivity_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('distinguishes physical connectivity from VPN-only changes', () {
    expect(hasPhysicalConnectivity(const []), isFalse);
    expect(hasPhysicalConnectivity(const [ConnectivityResult.none]), isFalse);
    expect(hasPhysicalConnectivity(const [ConnectivityResult.vpn]), isFalse);
    expect(
      hasPhysicalConnectivity(const [
        ConnectivityResult.wifi,
        ConnectivityResult.vpn,
      ]),
      isTrue,
    );
    expect(
      hasPhysicalConnectivity(const [ConnectivityResult.ethernet]),
      isTrue,
    );
    expect(hasPhysicalConnectivity(const [ConnectivityResult.mobile]), isTrue);
    expect(hasPhysicalConnectivity(const [ConnectivityResult.other]), isTrue);
  });
}
