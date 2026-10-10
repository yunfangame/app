import 'dart:async';

import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/common/subscription_entry_reminder.dart';
import 'package:fl_clash/common/subscription_v2.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/subscription_entry_reminder_dialog.dart';
import 'package:flutter/material.dart';
import 'package:window_ext/window_ext.dart';
import 'package:window_manager/window_manager.dart';

class SubscriptionEntryReminderHost extends StatefulWidget {
  const SubscriptionEntryReminderHost({
    super.key,
    this.authService,
    this.preferenceStore,
    this.now,
    this.observeDesktopWindow,
    this.requestTimeout = const Duration(seconds: 8),
    required this.child,
  });

  final XboardAuthService? authService;
  final SubscriptionEntryReminderStore? preferenceStore;
  final DateTime Function()? now;
  final bool? observeDesktopWindow;
  final Duration requestTimeout;
  final Widget child;

  @override
  State<SubscriptionEntryReminderHost> createState() =>
      _SubscriptionEntryReminderHostState();
}

class _SubscriptionEntryReminderHostState
    extends State<SubscriptionEntryReminderHost>
    with WidgetsBindingObserver, WindowListener, WindowExtListener {
  late final XboardAuthService _authService;
  late final SubscriptionEntryReminderStore _preferenceStore;
  late final bool _observeDesktopWindow;
  String? _account;
  int _entryRevision = 0;
  bool _foreground = true;
  bool _entryScheduled = false;
  _PendingSubscriptionReminder? _pending;
  DialogRoute<SubscriptionEntryReminderChoice>? _dialog;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  String? get _currentAccount {
    final session = globalState.xboardSession;
    return session == null
        ? null
        : SubscriptionEntryReminderStore.accountKey(
            session,
            fallbackAccountKey: globalState.xboardRuleAccountKey,
          );
  }

  @override
  void initState() {
    super.initState();
    final requestTimeout = widget.requestTimeout;
    final attemptTimeout = requestTimeout < const Duration(seconds: 4)
        ? requestTimeout
        : const Duration(seconds: 4);
    _authService =
        widget.authService ??
        XboardAuthService(
          apiRequestTimeout: attemptTimeout,
          apiOperationTimeout: requestTimeout,
          subscriptionV2Client: SubscriptionV2Client(
            gatewayRequestTimeout: attemptTimeout,
            operationTimeout: requestTimeout,
          ),
        );
    _preferenceStore =
        widget.preferenceStore ?? SubscriptionEntryReminderStore();
    _observeDesktopWindow = widget.observeDesktopWindow ?? system.isDesktop;
    _foreground = !{
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    }.contains(WidgetsBinding.instance.lifecycleState);
    _account = _currentAccount;
    WidgetsBinding.instance.addObserver(this);
    globalState.xboardSessionRevisionNotifier.addListener(_sessionChanged);
    globalState.offlineModeNotifier.addListener(_offlineChanged);
    if (_observeDesktopWindow) {
      windowManager.addListener(this);
      windowExtManager.addListener(this);
    }
    _scheduleEntry();
  }

  void _sessionChanged() {
    final nextAccount = _currentAccount;
    final changedAccount = nextAccount != _account;
    _account = nextAccount;
    _invalidateEntry();
    if (changedAccount && nextAccount != null) _scheduleEntry();
  }

  void _offlineChanged() {
    _invalidateEntry();
    if (!globalState.isOfflineMode) _scheduleEntry();
  }

  void _invalidateEntry() {
    _entryRevision++;
    _pending = null;
    final dialog = _dialog;
    _dialog = null;
    if (dialog != null) {
      scheduleMicrotask(() {
        final navigator = dialog.navigator;
        if (dialog.isActive && navigator?.mounted == true) {
          navigator!.removeRoute(dialog);
        }
      });
    }
  }

  void _scheduleEntry() {
    if (_entryScheduled || !mounted || !_foreground) return;
    _entryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entryScheduled = false;
      if (mounted && _foreground) unawaited(_checkEntry());
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _isCurrent(int entry, XboardLoginResult session, int sessionRevision) =>
      mounted &&
      _foreground &&
      !globalState.isOfflineMode &&
      entry == _entryRevision &&
      globalState.isActiveXboardSession(session, sessionRevision);

  Future<void> _checkEntry() async {
    final session = globalState.xboardSession;
    final account = _currentAccount;
    if (session == null || account == null || globalState.isOfflineMode) return;
    _invalidateEntry();
    final entry = _entryRevision;
    final sessionRevision = globalState.xboardSessionRevision;
    try {
      if (await _preferenceStore.isDisabled(account) ||
          !_isCurrent(entry, session, sessionRevision)) {
        return;
      }
      final previousSnapshot = globalState.xboardSubscription;
      final subscription = await _authService
          .fetchSubscription(
            endpoint: session.endpoint,
            authData: session.authData,
            userToken: session.token,
            secureSubscription: session.secureSubscription,
          )
          .timeout(widget.requestTimeout);
      if (!_isCurrent(entry, session, sessionRevision) ||
          !identical(previousSnapshot, globalState.xboardSubscription)) {
        return;
      }
      final email = subscription.email?.trim().toLowerCase();
      final sessionEmail = session.subscription.email?.trim().toLowerCase();
      if (email?.isNotEmpty == true &&
          sessionEmail?.isNotEmpty == true &&
          email != sessionEmail) {
        return;
      }
      globalState.updateXboardSubscriptionSnapshot(session, subscription);
      final evaluation = evaluateSubscriptionEntryReminder(
        subscription,
        now: _now,
      );
      if (evaluation == null || !_isCurrent(entry, session, sessionRevision)) {
        return;
      }
      setState(() {
        _pending = _PendingSubscriptionReminder(
          entry: entry,
          session: session,
          sessionRevision: sessionRevision,
          account: account,
          subscription: subscription,
        );
      });
    } catch (error) {
      if (_isCurrent(entry, session, sessionRevision)) {
        commonPrint.event(
          'subscription.entry_reminder.check_failed',
          fields: {'error_type': error.runtimeType.toString()},
        );
      }
    }
  }

  Future<void> _showPending(_PendingSubscriptionReminder pending) async {
    if (!identical(pending, _pending) ||
        !_isCurrent(pending.entry, pending.session, pending.sessionRevision) ||
        ModalRoute.of(context)?.isCurrent == false ||
        _dialog != null) {
      return;
    }
    _pending = null;
    if (!identical(pending.subscription, globalState.xboardSubscription)) {
      return;
    }
    final now = _now;
    final evaluation = evaluateSubscriptionEntryReminder(
      pending.subscription,
      now: now,
    );
    if (evaluation == null) return;
    final dialog = DialogRoute<SubscriptionEntryReminderChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SubscriptionEntryReminderDialog(
        subscription: pending.subscription,
        evaluation: evaluation,
        now: now,
      ),
    );
    _dialog = dialog;
    try {
      final choice = await Navigator.of(
        context,
        rootNavigator: true,
      ).push(dialog);
      if (choice?.dontRemind == true &&
          _isCurrent(pending.entry, pending.session, pending.sessionRevision)) {
        await _preferenceStore.disable(pending.account);
      }
    } catch (error) {
      commonPrint.event(
        'subscription.entry_reminder.presentation_failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
    } finally {
      if (identical(_dialog, dialog)) _dialog = null;
    }
  }

  void _background() {
    if (!_foreground) return;
    _foreground = false;
    _invalidateEntry();
  }

  void _returnToApp() {
    if (_foreground) return;
    _foreground = true;
    _scheduleEntry();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _returnToApp();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _background();
    }
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'hide') _background();
    if (eventName == 'show') _returnToApp();
  }

  @override
  void onWindowMinimize() => _background();

  @override
  void onWindowRestore() => _returnToApp();

  @override
  void onReopen() => _returnToApp();

  @override
  void dispose() {
    _invalidateEntry();
    globalState.xboardSessionRevisionNotifier.removeListener(_sessionChanged);
    globalState.offlineModeNotifier.removeListener(_offlineChanged);
    WidgetsBinding.instance.removeObserver(this);
    if (_observeDesktopWindow) {
      windowManager.removeListener(this);
      windowExtManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = ModalRoute.of(context);
    final pending = _pending;
    if (pending != null && currentRoute?.isCurrent != false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showPending(pending));
      });
    }
    return widget.child;
  }
}

class _PendingSubscriptionReminder {
  const _PendingSubscriptionReminder({
    required this.entry,
    required this.session,
    required this.sessionRevision,
    required this.account,
    required this.subscription,
  });

  final int entry;
  final XboardLoginResult session;
  final int sessionRevision;
  final String account;
  final XboardSubscriptionData subscription;
}
