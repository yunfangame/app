import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'diagnostic_log.dart';

enum ApiNetworkFailure {
  dns,
  timeout,
  tls,
  connectionRefused,
  connectionReset,
  permissionDenied,
  network,
  http,
  cancelled,
  configDecrypt,
  configSignature,
  noEndpoints,
  configuration,
}

class ApiNetworkDiagnostic {
  const ApiNetworkDiagnostic({
    required this.failure,
    required this.stage,
    this.osErrorCode,
    this.statusCode,
    this.elapsedMilliseconds,
    this.endpointRef,
    this.attemptId,
  });

  final ApiNetworkFailure failure;
  final String stage;
  final int? osErrorCode;
  final int? statusCode;
  final int? elapsedMilliseconds;
  final String? endpointRef;
  final String? attemptId;

  String get code => switch (failure) {
    ApiNetworkFailure.connectionRefused => 'connection_refused',
    ApiNetworkFailure.connectionReset => 'connection_reset',
    ApiNetworkFailure.permissionDenied => 'permission_denied',
    ApiNetworkFailure.configDecrypt => 'config_decrypt',
    ApiNetworkFailure.configSignature => 'config_signature',
    ApiNetworkFailure.noEndpoints => 'no_endpoints',
    _ => failure.name,
  };

  Map<String, Object?> toDiagnosticFields() => {
    'reason': code,
    'stage': stage,
    if (osErrorCode != null) 'os_error_code': osErrorCode,
    if (statusCode != null) 'http_status': statusCode,
    if (elapsedMilliseconds != null) 'elapsed_ms': elapsedMilliseconds,
    if (endpointRef != null) 'endpoint_ref': endpointRef,
    if (attemptId != null) 'attempt_id': attemptId,
  };
}

typedef ApiDiagnosticRecorder =
    void Function(String event, Map<String, Object?> fields);

int _attemptSequence = 0;

String newApiDiagnosticAttemptId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_${++_attemptSequence}';

String apiDiagnosticEndpointRef(Uri endpoint) => diagnosticFingerprint(
  '${endpoint.scheme}://${endpoint.host}:${endpoint.port}',
);

void recordApiDiagnosticEvent(String event, Map<String, Object?> fields) {
  unawaited(
    diagnosticLog.record(event, fields: fields).catchError((Object _) {}),
  );
}

void emitApiDiagnosticEvent(
  ApiDiagnosticRecorder recorder,
  String event,
  Map<String, Object?> fields,
) {
  try {
    recorder(event, fields);
  } catch (_) {}
}

ApiNetworkDiagnostic classifyApiNetworkFailure(
  Object error, {
  required String stage,
  Uri? endpoint,
  int? statusCode,
  int? elapsedMilliseconds,
  String? attemptId,
}) {
  var current = error;
  var failure = ApiNetworkFailure.network;
  int? osCode;
  for (var depth = 0; depth < 6; depth++) {
    if (current is DioException) {
      statusCode ??= current.response?.statusCode;
      failure = switch (current.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => ApiNetworkFailure.timeout,
        DioExceptionType.badCertificate => ApiNetworkFailure.tls,
        DioExceptionType.cancel => ApiNetworkFailure.cancelled,
        _ => failure,
      };
      final nested = current.error;
      if (nested == null || identical(nested, current)) break;
      current = nested;
      continue;
    }
    if (current is TimeoutException) {
      failure = ApiNetworkFailure.timeout;
    } else if (current is TlsException) {
      failure = ApiNetworkFailure.tls;
      osCode = current.osError?.errorCode;
    } else if (current is SocketException) {
      osCode = current.osError?.errorCode;
      final message = current.message.toLowerCase();
      failure = switch (osCode) {
        10013 || 13 || 1 => ApiNetworkFailure.permissionDenied,
        10060 || 110 || 60 => ApiNetworkFailure.timeout,
        10061 || 111 || 61 => ApiNetworkFailure.connectionRefused,
        10054 || 104 || 54 => ApiNetworkFailure.connectionReset,
        11001 || 11002 || 11004 || -2 || -3 => ApiNetworkFailure.dns,
        _
            when message.contains('failed host lookup') ||
                message.contains('name or service not known') ||
                message.contains('nodename nor servname') =>
          ApiNetworkFailure.dns,
        _ => failure,
      };
    }
    break;
  }
  final validStatus =
      statusCode != null && statusCode >= 100 && statusCode < 600
      ? statusCode
      : null;
  if (validStatus != null) failure = ApiNetworkFailure.http;
  return ApiNetworkDiagnostic(
    failure: failure,
    stage: stage,
    osErrorCode: osCode,
    statusCode: validStatus,
    elapsedMilliseconds: elapsedMilliseconds,
    endpointRef: endpoint == null ? null : apiDiagnosticEndpointRef(endpoint),
    attemptId: attemptId,
  );
}
