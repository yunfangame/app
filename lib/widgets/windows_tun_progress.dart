import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';

VoidCallback showWindowsTunProgress(BuildContext context) {
  final navigator = Navigator.of(context);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const WindowsTunProgressDialog(),
  );
  unawaited(navigator.push(route));
  return () {
    if (navigator.mounted && route.isActive) navigator.removeRoute(route);
  };
}

class WindowsTunProgressDialog extends StatelessWidget {
  const WindowsTunProgressDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l10n.tunStarting),
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 20),
            Flexible(child: Text(l10n.tunStartingDescription)),
          ],
        ),
      ),
    );
  }
}
