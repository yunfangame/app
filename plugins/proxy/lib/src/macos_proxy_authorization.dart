import 'dart:io';

import 'package:flutter/services.dart';

import 'proxy_command.dart';

typedef MacosProxyDiagnostic =
    void Function(String event, Map<String, Object?> fields);

class MacosProxyAuthorization {
  MacosProxyAuthorization({this.onDiagnostic, MethodChannel? channel})
    : channel =
          channel ??
          const MethodChannel('com.fengwo.accelerator/proxy_authorization') {
    this.channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      if (call.method != 'diagnostic' || args is! Map) return;
      final event = args['event'];
      final fields = args['fields'];
      if (!const {
            'authorization.started',
            'authorization.completed',
            'service.discovery.completed',
          }.contains(event) ||
          fields is! Map) {
        return;
      }
      onDiagnostic?.call('system_proxy.native.$event', {
        'backend': 'system_configuration',
        if (fields['status'] is int) 'status': fields['status'],
        ..._discoveryFields(fields),
      });
    });
  }

  final MethodChannel channel;
  final MacosProxyDiagnostic? onDiagnostic;

  Future<void> invalidate() async {
    try {
      await channel.invokeMethod<Object?>('invalidate');
      onDiagnostic?.call('system_proxy.native.invalidated', {});
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      onDiagnostic?.call('system_proxy.native.invalidate.failed', {
        'error_type': error.runtimeType.toString(),
      });
    }
  }

  Future<bool?> readAutoDiscovery(String service) async {
    final response = await _readService(service);
    return response?['enabled'] as bool?;
  }

  Future<MacosProxyServiceIdentity?> readServiceIdentity(String service) async {
    final response = await _readService(service);
    final setID = response?['networkSetID'];
    if (response == null ||
        setID is! String ||
        setID.isEmpty ||
        setID.length > 128 ||
        setID.contains('\u0000')) {
      return null;
    }
    return (serviceID: response['serviceID'] as String, networkSetID: setID);
  }

  static final _serviceIdPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Future<Map?> _readService(String service) async {
    Object? response;
    try {
      response = await channel.invokeMethod<Object?>('readAutoDiscovery', {
        'service': service,
      });
    } on PlatformException catch (error) {
      onDiagnostic?.call('system_proxy.native.auto_discovery.failed', {
        'error_type': error.runtimeType.toString(),
      });
      return null;
    } on MissingPluginException {
      return null;
    }
    if (response is! Map ||
        response['serviceName'] != service ||
        response['enabled'] is! bool ||
        response['serviceID'] is! String ||
        !_serviceIdPattern.hasMatch(response['serviceID'] as String)) {
      if (response is Map) {
        onDiagnostic?.call('system_proxy.native.auto_discovery.unavailable', {
          ..._discoveryFields(response),
        });
      }
      return null;
    }
    onDiagnostic?.call('system_proxy.native.auto_discovery.read', {
      'backend': 'system_configuration',
      'enabled': response['enabled'],
      'setting_present': response['settingPresent'] == true,
    });
    return response;
  }

  Future<ProxyCommandResult> write(List<ProxyCommand> commands) async {
    if (commands.isEmpty ||
        commands.map((command) => command.macosIdentity).toSet().length != 1) {
      return ProxyCommandResult(
        success: false,
        command: commands.firstOrNull,
        diagnosticCommand: 'SystemConfiguration writeCommands',
        processResult: ProcessResult(0, 1, 'service_identity_changed', ''),
      );
    }
    final identity = commands.first.macosIdentity;
    final watch = Stopwatch()..start();
    onDiagnostic?.call('system_proxy.native.write.started', {
      'backend': 'system_configuration',
      'command_count': commands.length,
    });
    try {
      final response = await channel.invokeMethod<Object?>('writeCommands', {
        'commands': commands.map((command) => command.args).toList(),
        if (identity != null)
          'serviceIdentity': {
            'serviceID': identity.serviceID,
            'networkSetID': identity.networkSetID,
          },
      });
      final success = response is Map && response['success'] == true;
      final committed = response is Map && response['committed'] == true;
      final error = response is Map && response['systemError'] is int
          ? response['systemError'] as int
          : null;
      final reason = response is Map && response['reason'] is String
          ? response['reason'] as String
          : 'native_response_invalid';
      onDiagnostic?.call('system_proxy.native.write.completed', {
        'backend': 'system_configuration',
        'success': success,
        'committed': committed,
        'authorization_attempted':
            response is Map && response['authorizationAttempted'] == true,
        'authorization_used':
            response is Map && response['authorizationUsed'] == true,
        'authorization_cancelled':
            response is Map && response['authorizationCancelled'] == true,
        'write_skipped': response is Map && response['writeSkipped'] == true,
        if (!success) 'reason': reason,
        if (response is Map) ..._discoveryFields(response),
        'system_error': ?error,
        'elapsed_ms': watch.elapsedMilliseconds,
      });
      return ProxyCommandResult(
        success: success,
        command: success || committed ? commands.last : commands.first,
        diagnosticCommand: 'SystemConfiguration writeCommands',
        systemError: error,
        processResult: ProcessResult(
          0,
          success ? 0 : (error != null && error != 0 ? error : 1),
          success ? '' : reason,
          '',
        ),
      );
    } on PlatformException catch (error) {
      return _unavailable(commands, error);
    } on MissingPluginException catch (error) {
      return _unavailable(commands, error);
    }
  }

  static Map<String, Object?> _discoveryFields(Map fields) => {
    if (fields['success'] is bool) 'success': fields['success'],
    for (final key in ['scoped_match_count', 'global_match_count'])
      if (fields[key] is int && (fields[key] as int) >= 0) key: fields[key],
    if (const {
      'unique_current_set',
      'primary_current_set',
      'snapshot_id',
    }.contains(fields['selection']))
      'selection': fields['selection'],
    if (const {
      'service_not_found',
      'service_not_unique',
      'service_identity_changed',
      'network_location_changed',
      'current_set_unavailable',
      'service_discovery',
    }.contains(fields['reason']))
      'reason': fields['reason'],
  };

  ProxyCommandResult _unavailable(List<ProxyCommand> commands, Object error) {
    onDiagnostic?.call('system_proxy.native.write.failed', {
      'error_type': error.runtimeType.toString(),
    });
    return ProxyCommandResult(
      success: false,
      command: commands.first,
      diagnosticCommand: 'SystemConfiguration writeCommands',
      processResult: ProcessResult(
        0,
        1,
        'native_authorization_unavailable',
        '',
      ),
    );
  }
}

class MacosAuthorizedCommandRunner extends ProxyCommandRunner {
  MacosAuthorizedCommandRunner(this.base, this.authorization)
    : super(base.process);

  final ProxyCommandRunner base;
  final MacosProxyAuthorization authorization;

  @override
  Future<ProxyCommandResult> runDetailed(Iterable<ProxyCommand> commands) {
    final batch = commands.toList();
    if (batch.isNotEmpty &&
        batch.every(
          (command) =>
              command.executable == '/usr/sbin/networksetup' &&
              !command.runInShell &&
              command.args.isNotEmpty &&
              command.args.first.startsWith('-set'),
        )) {
      return authorization.write(batch);
    }
    return base.runDetailed(batch);
  }
}
