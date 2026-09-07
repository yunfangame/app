import 'package:fl_clash/common/api_network_diagnostic.dart';
import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';

String apiNetworkDiagnosticMessage(
  BuildContext context,
  ApiNetworkDiagnostic diagnostic,
) {
  final l10n = context.appLocalizations;
  return switch (diagnostic.failure) {
    ApiNetworkFailure.dns => l10n.apiFailureDns,
    ApiNetworkFailure.timeout => l10n.apiFailureTimeout,
    ApiNetworkFailure.tls => l10n.apiFailureTls,
    ApiNetworkFailure.connectionRefused => l10n.apiFailureRefused,
    ApiNetworkFailure.connectionReset => l10n.apiFailureReset,
    ApiNetworkFailure.permissionDenied => l10n.apiFailurePermission,
    ApiNetworkFailure.network => l10n.apiFailureNetwork,
    ApiNetworkFailure.http => switch (diagnostic.statusCode) {
      403 || 407 => l10n.apiFailureHttpDenied(diagnostic.statusCode!),
      429 => l10n.apiFailureRateLimited,
      final int status => l10n.apiFailureHttp(status),
      null => l10n.apiFailureNetwork,
    },
    ApiNetworkFailure.cancelled => l10n.apiFailureCancelled,
    ApiNetworkFailure.configDecrypt => l10n.apiFailureDecrypt,
    ApiNetworkFailure.configSignature => l10n.apiFailureSignature,
    ApiNetworkFailure.noEndpoints => l10n.apiFailureNoEndpoints,
    ApiNetworkFailure.configuration => l10n.apiFailureConfiguration,
  };
}

class ApiDiagnosticExportButton extends StatefulWidget {
  const ApiDiagnosticExportButton({super.key, required this.onExportLogs});

  final Future<bool> Function() onExportLogs;

  @override
  State<ApiDiagnosticExportButton> createState() =>
      _ApiDiagnosticExportButtonState();
}

class _ApiDiagnosticExportButtonState extends State<ApiDiagnosticExportButton> {
  bool _exporting = false;

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final saved = await widget.onExportLogs();
      if (mounted && saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.appLocalizations.exportSuccess)),
        );
      }
    } catch (error) {
      commonPrint.event(
        'auth.diagnostic.export.failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.appLocalizations.apiLogExportFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _exporting ? null : _export,
      icon: _exporting
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_outlined),
      label: Text(context.appLocalizations.exportLogs),
    );
  }
}
