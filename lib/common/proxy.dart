import 'package:fl_clash/common/system.dart';
import 'package:proxy/proxy.dart';

final proxy = system.isDesktop ? Proxy() : null;

typedef SystemProxyRefreshHandler = Future<void> Function();

class SystemProxyRefreshSignal {
  SystemProxyRefreshHandler? _handler;

  void attach(SystemProxyRefreshHandler handler) {
    _handler = handler;
  }

  void detach() {
    _handler = null;
  }

  Future<void> request() {
    return _handler?.call() ?? Future<void>.value();
  }
}

final systemProxyRefreshSignal = SystemProxyRefreshSignal();
