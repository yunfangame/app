import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/xboard_tickets.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String _ticketTime(int seconds) => seconds <= 0
    ? ''
    : DateFormat(
        'yyyy-MM-dd HH:mm',
      ).format(DateTime.fromMillisecondsSinceEpoch(seconds * 1000));

class TicketUnreadBadge extends StatelessWidget {
  const TicketUnreadBadge({
    super.key,
    required this.controller,
    required this.child,
  });
  final XboardTicketController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Badge(
      key: const ValueKey('personal-center-unread-badge'),
      isLabelVisible: controller.unreadCount > 0,
      backgroundColor: Colors.red,
      child: child,
    ),
  );
}

class FengWoTicketPanel extends StatefulWidget {
  const FengWoTicketPanel({super.key, required this.controller});
  final XboardTicketController controller;

  @override
  State<FengWoTicketPanel> createState() => _FengWoTicketPanelState();
}

class _FengWoTicketPanelState extends State<FengWoTicketPanel> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TicketComposer(controller: widget.controller),
    );
    if (!mounted || created != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.appLocalizations.ticketCreated)),
    );
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.support_agent_rounded,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.ticketList,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('ticket-refresh'),
                    tooltip: l10n.ticketRefresh,
                    onPressed: controller.loading
                        ? null
                        : () => controller.refresh(),
                    icon: const Icon(Icons.refresh),
                  ),
                  if (constraints.maxWidth < 400)
                    IconButton.filledTonal(
                      key: const ValueKey('ticket-create'),
                      tooltip: l10n.ticketNew,
                      onPressed: _create,
                      icon: const Icon(Icons.add),
                    )
                  else
                    FilledButton.tonalIcon(
                      key: const ValueKey('ticket-create'),
                      onPressed: _create,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.ticketNew),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text('${l10n.ticketOpen} (${controller.openCount})'),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text(
                    '${l10n.ticketClosed} (${controller.closedCount})',
                  ),
                ),
              ],
              selected: {controller.status},
              onSelectionChanged: (selection) {
                if (_scroll.hasClients) _scroll.jumpTo(0);
                unawaited(controller.refresh(filter: selection.first));
              },
            ),
            const SizedBox(height: 10),
            if (controller.loading) const LinearProgressIndicator(minHeight: 2),
            if (controller.failed)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.ticketLoadFailed,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                  TextButton(
                    onPressed: () => controller.refresh(),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            Expanded(
              child: controller.tickets.isEmpty
                  ? Center(
                      child: Text(
                        controller.loading
                            ? l10n.loading
                            : controller.failed
                            ? ''
                            : l10n.ticketEmpty,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    )
                  : Scrollbar(
                      controller: _scroll,
                      thumbVisibility: true,
                      child: ListView.separated(
                        key: const ValueKey('ticket-list-scroll'),
                        controller: _scroll,
                        primary: false,
                        itemCount:
                            controller.tickets.length +
                            (controller.hasMore ? 1 : 0),
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == controller.tickets.length) {
                            return TextButton(
                              onPressed: controller.loading
                                  ? null
                                  : () => controller.refresh(more: true),
                              child: Text(l10n.ticketMore),
                            );
                          }
                          final ticket = controller.tickets[index];
                          return ListTile(
                            key: ValueKey('ticket-${ticket.id}'),
                            contentPadding: const EdgeInsetsDirectional.only(
                              end: 12,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    ticket.subject,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (ticket.unread) ...[
                                  const SizedBox(width: 10),
                                  Semantics(
                                    label: l10n.ticketUnread,
                                    child: Container(
                                      key: ValueKey(
                                        'ticket-unread-${ticket.id}',
                                      ),
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                '${ticket.closed
                                    ? l10n.ticketClosed
                                    : ticket.replied
                                    ? l10n.ticketReplied
                                    : l10n.ticketWaiting} · ${_ticketTime(ticket.updatedAt)}',
                                maxLines: 2,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => _TicketDetailDialog(
                                controller: controller,
                                id: ticket.id,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _TicketComposer extends StatefulWidget {
  const _TicketComposer({required this.controller});
  final XboardTicketController controller;
  @override
  State<_TicketComposer> createState() => _TicketComposerState();
}

class _TicketComposerState extends State<_TicketComposer> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  late final XboardLoginResult? _session;

  @override
  void initState() {
    super.initState();
    _session = widget.controller.session;
  }

  bool _busy = false;
  bool _failed = false;
  int _level = 1;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final session = _session;
    if (session == null || !widget.controller.isCurrent(session)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.controller.mutate('save', {
        'subject': _subject.text.trim(),
        'level': _level,
        'message': _message.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(l10n.ticketNew),
        scrollable: true,
        content: SizedBox(
          width: 520,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('ticket-subject-input'),
                  controller: _subject,
                  enabled: !_busy,
                  maxLength: 255,
                  decoration: InputDecoration(labelText: l10n.ticketSubject),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? l10n.ticketRequired
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _level,
                  decoration: InputDecoration(labelText: l10n.ticketPriority),
                  items: [
                    for (final entry in {
                      0: l10n.ticketLow,
                      1: l10n.ticketNormal,
                      2: l10n.ticketHigh,
                    }.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _level = value ?? 1),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('ticket-message-input'),
                  controller: _message,
                  enabled: !_busy,
                  minLines: 5,
                  maxLines: 8,
                  maxLength: 10000,
                  decoration: InputDecoration(
                    labelText: l10n.ticketContent,
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? l10n.ticketRequired
                      : null,
                ),
                if (_failed)
                  Text(
                    l10n.ticketActionFailed,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('ticket-submit'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.ticketSubmit),
          ),
        ],
      ),
    );
  }
}

class _TicketDetailDialog extends StatefulWidget {
  const _TicketDetailDialog({required this.controller, required this.id});
  final XboardTicketController controller;
  final int id;
  @override
  State<_TicketDetailDialog> createState() => _TicketDetailDialogState();
}

class _TicketDetailDialogState extends State<_TicketDetailDialog> {
  final _reply = TextEditingController();
  final _scroll = ScrollController();
  late final _session = widget.controller.session;
  XboardTicketDetail? _detail;
  Timer? _timer;
  bool _loading = false;
  bool _failed = false;
  bool _readFailed = false;
  bool _actionFailed = false;
  bool _busy = false;
  int _revision = 0;
  int _acknowledgedReplyId = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sessionChanged);
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_busy && !_loading) unawaited(_load());
    });
  }

  void _sessionChanged() {
    if (_current) return;
    _timer?.cancel();
    _revision++;
    if (mounted && _detail != null) {
      setState(() {
        _detail = null;
        _loading = false;
      });
    }
  }

  bool get _current =>
      mounted && _session != null && widget.controller.isCurrent(_session);

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_sessionChanged);
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_current || _loading) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final detail = await widget.controller.detail(widget.id);
      if (!_current || revision != _revision) return;
      setState(() => _detail = detail);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_current && revision == _revision) unawaited(_markRead(detail));
      });
    } catch (_) {
      if (_current && revision == _revision) setState(() => _failed = true);
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(XboardTicketDetail detail) async {
    if (!_current || detail.latestReplyId <= _acknowledgedReplyId) return;
    try {
      await widget.controller.markRead(detail);
      if (_current) {
        setState(() {
          _readFailed = false;
          _acknowledgedReplyId = detail.latestReplyId;
        });
      }
    } catch (_) {
      if (_current) setState(() => _readFailed = true);
    }
  }

  Future<void> _mutate(String action) async {
    if (!_current || _busy) return;
    if (action == 'reply' && _reply.text.trim().isEmpty) return;
    setState(() {
      _revision++;
      _loading = false;
      _busy = true;
      _actionFailed = false;
    });
    try {
      await widget.controller.mutate(action, {
        'id': widget.id,
        if (action == 'reply') 'message': _reply.text.trim(),
      });
      if (!_current) return;
      if (action == 'reply') _reply.clear();
      await _load();
    } catch (_) {
      if (_current) setState(() => _actionFailed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeTicket() async {
    final l10n = context.appLocalizations;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.ticketClose),
        content: Text(l10n.ticketCloseConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.ticketClose),
          ),
        ],
      ),
    );
    if (confirmed == true && _current) await _mutate('close');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colors = Theme.of(context).colorScheme;
    final detail = _detail;
    final viewport = MediaQuery.sizeOf(context);
    final compact =
        viewport.height - MediaQuery.viewInsetsOf(context).bottom < 400;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        insetPadding: compact
            ? EdgeInsets.zero
            : MediaQuery.sizeOf(context).width < 600
            ? const EdgeInsets.all(8)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: SizedBox(
          width: 760,
          height: MediaQuery.sizeOf(context).height * .82,
          child: Padding(
            padding: EdgeInsets.all(compact ? 10 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        detail?.subject ?? l10n.ticketList,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.ticketRefresh,
                      onPressed: _busy || _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      key: const ValueKey('ticket-detail-dismiss'),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (detail != null && !compact)
                  Text(
                    '#${detail.id} · ${detail.closed
                        ? l10n.ticketClosed
                        : detail.canReply
                        ? l10n.ticketReplied
                        : l10n.ticketWaiting}',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                SizedBox(height: compact ? 4 : 12),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                if (_failed)
                  TextButton(
                    onPressed: _load,
                    child: Text(l10n.ticketLoadFailed),
                  ),
                if (_readFailed && detail != null)
                  TextButton(
                    onPressed: () => _markRead(detail),
                    child: Text(l10n.ticketReadFailed),
                  ),
                Expanded(
                  child: detail == null
                      ? const SizedBox.shrink()
                      : Scrollbar(
                          controller: _scroll,
                          child: ListView.builder(
                            key: const ValueKey('ticket-detail-messages'),
                            controller: _scroll,
                            reverse: true,
                            itemCount: detail.messages.length,
                            itemBuilder: (context, index) {
                              final message = detail
                                  .messages[detail.messages.length - 1 - index];
                              return Align(
                                alignment: message.isMe
                                    ? AlignmentDirectional.centerEnd
                                    : AlignmentDirectional.centerStart,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 540,
                                  ),
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: message.isMe
                                        ? colors.primaryContainer
                                        : colors.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${message.isMe ? l10n.ticketYou : l10n.ticketSupport} · ${_ticketTime(message.createdAt)}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                      const SizedBox(height: 6),
                                      SelectableText(message.text),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
                if (_actionFailed)
                  Text(
                    l10n.ticketActionFailed,
                    style: TextStyle(color: colors.error),
                  ),
                if (detail != null && !detail.closed) ...[
                  Divider(height: compact ? 4 : 16),
                  if (detail.canReply)
                    TextField(
                      key: const ValueKey('ticket-reply-input'),
                      controller: _reply,
                      enabled: !_busy,
                      minLines: compact || viewport.width < 600 ? 1 : 2,
                      maxLines: compact ? 1 : 4,
                      maxLength: 10000,
                      decoration: InputDecoration(
                        hintText: l10n.ticketReplyHint,
                        counterText: compact ? '' : null,
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: _busy ? null : _closeTicket,
                          child: Text(
                            l10n.ticketClose,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: detail.canReply
                            ? FilledButton(
                                key: const ValueKey('ticket-reply-send'),
                                onPressed: _busy
                                    ? null
                                    : () => _mutate('reply'),
                                child: Text(
                                  l10n.ticketReply,
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : Text(
                                l10n.ticketWaiting,
                                textAlign: TextAlign.end,
                              ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
