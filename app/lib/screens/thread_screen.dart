import 'dart:async';

import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/messaging_repository.dart';
import '../data/models.dart';
import '../data/school_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';
import '../widgets/help.dart';
import '../widgets/state_views.dart';

/// One private conversation. [readOnly] is used when an administrator opens a REPORTED conversation.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({super.key, required this.thread, this.readOnly = false});

  final ThreadSummary thread;
  final bool readOnly;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _poll;

  String get _me => AuthRepository.instance.userId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    if (!widget.readOnly) {
      _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load(quiet: true));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await MessagingRepository.instance.messages(widget.thread.threadId);
      if (!widget.readOnly) await MessagingRepository.instance.markRead(widget.thread.threadId);
      if (!mounted) return;
      final grew = list.length != _messages.length;
      setState(() {
        _messages = list;
        _loading = false;
      });
      if (grew) _toBottom();
    } catch (e) {
      if (!mounted || quiet) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await MessagingRepository.instance.send(widget.thread.threadId, text);
      _input.clear();
      await _load(quiet: true);
    } catch (e) {
      if (mounted) notify(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _report(ChatMessage m) async {
    final ok = await showFormSheet(
      context,
      title: 'Report this message',
      subtitle: 'Your school\'s administrator will be able to read this conversation to look into it.',
      submitLabel: 'Report',
      fields: const [FieldSpec('reason', 'What is wrong with it?', kind: FieldKind.multiline, required: true)],
      onSubmit: (v) async {
        try {
          await MessagingRepository.instance.report(m.id, v['reason']!);
        } catch (e) {
          throw FormError(friendlyError(e));
        }
      },
    );
    if (ok == true && mounted) notify(context, 'Thank you. The school has been told.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = widget.thread;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.otherName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          Text('About ${t.studentName}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]),
        actions: const [
          HelpButton(
            title: 'Messages',
            steps: [
              'This conversation is private between you and the other person.',
              'Be polite and keep it about the student.',
              'Press and hold a message from the other person to report it if it is not appropriate.',
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (widget.readOnly)
          Container(
            width: double.infinity,
            color: AppTheme.gold.withValues(alpha: 0.2),
            padding: const EdgeInsets.all(12),
            child: const Text('You can read this conversation because it was reported.'),
          ),
        if (t.isClosed)
          Container(
            width: double.infinity,
            color: cs.errorContainer,
            padding: const EdgeInsets.all(12),
            child: Text('This conversation was closed by the school.', style: TextStyle(color: cs.onErrorContainer)),
          ),
        Expanded(
          child: _loading
              ? const LoadingView()
              : _error != null
                  ? MessageView(icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) {
                        final m = _messages[i];
                        final mine = m.senderId == _me;
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: GestureDetector(
                            onLongPress: (!mine && !widget.readOnly) ? () => _report(m) : null,
                            child: Container(
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: mine ? AppTheme.green : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(mine ? 16 : 4),
                                  bottomRight: Radius.circular(mine ? 4 : 16),
                                ),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(m.body, style: TextStyle(color: mine ? Colors.white : cs.onSurface)),
                                const SizedBox(height: 4),
                                Text('${formatDate(m.createdAt)}  ${formatTime(m.createdAt)}',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: mine ? Colors.white70 : cs.onSurfaceVariant)),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        if (!widget.readOnly && !t.isClosed)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Write a message', counterText: ''),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
