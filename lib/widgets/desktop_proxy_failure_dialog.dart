import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/desktop_proxy_failure.dart';
import 'package:flutter/material.dart';

enum DesktopProxyFailureChoice { logs, retry, changePort }

class DesktopProxyFailureDialog extends StatelessWidget {
  const DesktopProxyFailureDialog({super.key, required this.failure});

  final DesktopProxyFailure failure;

  String _description(BuildContext context) {
    final l10n = context.appLocalizations;
    return switch (failure.kind) {
      DesktopProxyFailureKind.addressInUse => l10n.desktopProxyAddressInUse,
      DesktopProxyFailureKind.listenerAccessDenied =>
        l10n.desktopProxyListenerAccessDenied,
      DesktopProxyFailureKind.invalidBindAddress =>
        l10n.desktopProxyInvalidBindAddress,
      DesktopProxyFailureKind.addressNotAvailable =>
        l10n.desktopProxyAddressNotAvailable,
      DesktopProxyFailureKind.localPortUnavailable =>
        l10n.desktopProxyLocalPortUnavailable,
      DesktopProxyFailureKind.systemProxyAccessDenied =>
        l10n.desktopProxySystemAccessDenied,
      DesktopProxyFailureKind.systemProxyWriteFailed =>
        l10n.desktopProxySystemWriteFailed,
      DesktopProxyFailureKind.systemProxyReadbackFailed =>
        l10n.desktopProxySystemReadbackFailed,
      DesktopProxyFailureKind.systemProxyFailed =>
        l10n.desktopProxySystemFailed,
      DesktopProxyFailureKind.configurationFailed =>
        l10n.desktopProxyConfigurationFailed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return AlertDialog(
      key: const ValueKey('desktop-proxy-failure-dialog'),
      scrollable: true,
      icon: Icon(Icons.error_outline, color: context.colorScheme.error),
      title: Text(
        failure.isSystemProxyFailure
            ? l10n.desktopProxySystemFailureTitle
            : l10n.desktopProxyFailureTitle,
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_description(context)),
            const SizedBox(height: 16),
            Text(l10n.desktopProxyCurrentPort(failure.port)),
            const SizedBox(height: 8),
            Text(
              l10n.desktopProxyFailureCode(failure.code),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text(l10n.desktopProxyFailureLogsHint),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('desktop-proxy-failure-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('desktop-proxy-failure-logs'),
          onPressed: () =>
              Navigator.of(context).pop(DesktopProxyFailureChoice.logs),
          child: Text(l10n.desktopProxyFailureLogs),
        ),
        if (failure.canChangePort)
          OutlinedButton(
            key: const ValueKey('desktop-proxy-failure-change-port'),
            onPressed: () =>
                Navigator.of(context).pop(DesktopProxyFailureChoice.changePort),
            child: Text(l10n.desktopProxyChangePort),
          ),
        FilledButton(
          key: const ValueKey('desktop-proxy-failure-retry'),
          onPressed: () =>
              Navigator.of(context).pop(DesktopProxyFailureChoice.retry),
          child: Text(l10n.retry),
        ),
      ],
    );
  }
}

class DesktopProxyPortDialog extends StatefulWidget {
  const DesktopProxyPortDialog({
    super.key,
    required this.currentPort,
    required this.reservedPorts,
  });

  final int currentPort;
  final Set<int> reservedPorts;

  @override
  State<DesktopProxyPortDialog> createState() => _DesktopProxyPortDialogState();
}

class _DesktopProxyPortDialogState extends State<DesktopProxyPortDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPort.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final l10n = context.appLocalizations;
    final normalized = value?.trim() ?? '';
    final port = RegExp(r'^\d+$').hasMatch(normalized)
        ? int.tryParse(normalized)
        : null;
    if (port == null || port < 1024 || port > 49151) {
      return l10n.desktopProxyPortRange;
    }
    if (port == widget.currentPort) return l10n.desktopProxyPortUnchanged;
    if (widget.reservedPorts.contains(port)) {
      return l10n.desktopProxyPortReserved;
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(int.parse(_controller.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return AlertDialog(
      key: const ValueKey('desktop-proxy-port-dialog'),
      scrollable: true,
      title: Text(l10n.desktopProxyChangePort),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.desktopProxyCurrentPort(widget.currentPort)),
              const SizedBox(height: 12),
              Text(l10n.desktopProxyPortHint),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('desktop-proxy-port-input'),
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: InputDecoration(
                  labelText: l10n.port,
                  border: const OutlineInputBorder(),
                  errorMaxLines: 3,
                ),
                validator: _validate,
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('desktop-proxy-port-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('desktop-proxy-port-save'),
          onPressed: _submit,
          child: Text(l10n.desktopProxyPortSaveRetry),
        ),
      ],
    );
  }
}
