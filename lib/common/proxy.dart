import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/common/print.dart';
import 'package:proxy/proxy.dart';

final proxy = system.isDesktop
    ? Proxy(
        onDiagnostic: (event, fields) =>
            commonPrint.event(event, fields: fields),
      )
    : null;

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

typedef SystemProxyCleanupHandler =
    Future<bool> Function(int port, bool Function() isCancelled);

typedef SystemProxyShutdownHandler =
    Future<ProxyOperationResult> Function(int port, bool terminal);

class SystemProxyCleanupSignal {
  SystemProxyCleanupHandler? _handler;
  SystemProxyShutdownHandler? _shutdownHandler;

  void attach(
    SystemProxyCleanupHandler handler, {
    SystemProxyShutdownHandler? shutdown,
  }) {
    _handler = handler;
    _shutdownHandler = shutdown;
  }

  void detach() {
    _handler = null;
    _shutdownHandler = null;
  }

  Future<bool> request(int port, {required bool Function() isCancelled}) =>
      _handler?.call(port, isCancelled) ?? Future.value(false);

  Future<ProxyOperationResult?> shutdown(
    int port, {
    bool terminal = true,
  }) async => _shutdownHandler?.call(port, terminal);
}

final systemProxyCleanupSignal = SystemProxyCleanupSignal();
