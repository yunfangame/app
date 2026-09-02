import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

Future<void> showFengWoLogoutDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.logout_rounded),
      title: Text(dialogContext.appLocalizations.logoutConfirmTitle),
      content: Text(dialogContext.appLocalizations.logoutConfirmMessage),
      actions: [
        TextButton(
          key: const ValueKey('account-logout-cancel-button'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(dialogContext.appLocalizations.cancel),
        ),
        FilledButton(
          key: const ValueKey('account-logout-confirm-button'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(dialogContext.appLocalizations.logoutAccount),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    final logout = globalState.logoutXboard;
    if (logout != null) {
      await logout();
    } else {
      globalState.clearXboardSession();
    }
  } catch (error) {
    if (context.mounted) context.showNotifier(error.toString());
  }
}

class FengWoLogoutButton extends StatelessWidget {
  const FengWoLogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('account-logout-button'),
        onPressed: () => showFengWoLogoutDialog(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.error,
          backgroundColor: colors.errorContainer.withValues(alpha: 0.22),
          minimumSize: const Size.fromHeight(56),
          side: BorderSide(color: colors.error.withValues(alpha: 0.45)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        icon: const Icon(Icons.logout_rounded),
        label: Text(
          context.appLocalizations.logoutAccount,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
