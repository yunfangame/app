import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import 'constant.dart';

class AndroidUpdateTransport {
  AndroidUpdateTransport({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('$packageName/app');

  final MethodChannel _channel;
  final Set<String> _pending = {};
  static int _sequence = 0;
  bool _closed = false;

  Future<Object?> load(
    Uri uri, {
    String kind = 'update_manifest',
    CancelToken? cancelToken,
  }) async {
    if (_closed) throw StateError('Update transport is closed');
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final id = 'update-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}';
    _pending.add(id);
    if (cancelToken != null) {
      unawaited(cancelToken.whenCancel.then((_) => _cancel(id)));
    }
    try {
      final bytes = await _channel
          .invokeMethod<Uint8List>('fetchUpdateConfig', {
            'id': id,
            'url': uri.toString(),
            'kind': kind,
          })
          .timeout(const Duration(seconds: 8));
      if (_closed) throw StateError('Update transport is closed');
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('Empty update configuration');
      }
      return utf8.decode(bytes);
    } on PlatformException catch (error) {
      final request = RequestOptions(path: uri.toString());
      switch (error.code) {
        case 'UPDATE_TIMEOUT':
          throw TimeoutException('Update underlay request timed out');
        case 'UPDATE_TLS':
          throw const HandshakeException('Update TLS verification failed');
        case 'UPDATE_HTTP':
          final status = error.details is int ? error.details as int : 0;
          throw DioException.badResponse(
            statusCode: status,
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: status),
          );
        case 'UPDATE_CANCELLED':
          throw DioException.requestCancelled(
            requestOptions: request,
            reason: 'Update request cancelled',
          );
        case 'UPDATE_INVALID':
        case 'UPDATE_SIZE':
          throw const FormatException('Invalid update configuration response');
        default:
          throw const SocketException('Update underlay network unavailable');
      }
    } finally {
      await _cancel(id);
    }
  }

  Future<void> _cancel(String id) async {
    if (!_pending.remove(id)) return;
    try {
      await _channel.invokeMethod<void>('cancelUpdateConfig', id);
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  void close() {
    _closed = true;
    for (final id in _pending.toList()) {
      unawaited(_cancel(id));
    }
  }
}
