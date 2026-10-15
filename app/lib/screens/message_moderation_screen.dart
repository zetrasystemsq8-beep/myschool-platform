import 'package:flutter/material.dart';

import '../data/messaging_repository.dart';
import '../data/models.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../widgets/app_card.dart';
import '../widgets/async_list.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';
import '../widgets/help.dart';
import 'thread_screen.dart';

/// Administrators: switch messaging on or off, review reported messages, mute people.
/// Admins cannot browse private conversations; they can only open one that was reported.
class MessageModerationScreen extends StatefulWidget {
  const MessageModerationScreen({super.key, required this.school});

  final School school;

  @override
  State<MessageModerationScreen> createState() => _MessageModerationScreenState();
}

class _MessageModerationScreenState extends State<MessageModerationScreen> {
  bool? _enabled;
  int _refresh = 0;

  @override
  void initState() {
    super.initState();
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    try {
      final v = await MessagingRepository.instance.messagingEnabled(widget.school.id);
      if (mounted) setState(() => _enabled = v);
    } catch (_) {
      if (mounted) setState(() => _enabled = true);
    }
  }

  Future<void> _toggle(bool v) async {
    final ok = v ||
        await confirmDialog(context,
            title: 'Switch messaging off?',
            message: 'Parents and teachers will not be able to send messages until you switch it back on.',
            action: 'Switch off',
            destructive: true);
    if (!ok) return;
    try {
      await MessagingRepository.instance.setMessagingEnabled(widget.school.id, v);
      if (mounted) setState(() => _enabled = v);
    } catch (e) {
      if (mounted) notify(context, friendlyError(e), error: true);
    }
  }

  Future<void> _open(MessageReportRow r) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text('Reported message', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('${r.senderName} wrote, about ${r.studentName}:', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              AppCard(child: Text(r.messageBody)),
              const SizedBox(height: 10),
              Text('Reported by ${r.reporterName}: "${r.reason}"', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'view'), icon: const Icon(Icons.visibility_outlined), label: const Text('Read the conversation')),
              const SizedBox(height: 8),
              if (r.status == 'open') ...[
                FilledButton(onPressed: () => Navigator.pop(ctx, 'resolve'), child: const Text('Resolve this report')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => Navigator.pop(ctx, 'mute'), child: Text('Mute ${r.senderName}')),
              ] else if ((r.resolutionNote ?? '').isNotEmpty)
                Text('Resolved: ${r.resolutionNote}', style: theme.textTheme.bodySmall),
            ],
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    final repo = MessagingRepository.instance;
    if (choice == 'view') {
      final thread = ThreadSummary(
        threadId: r.threadId,
        studentName: r.studentName,
        otherName: '${r.parentName} and ${r.teacherName}',
        otherRole: '',
        status: 'open',
        unread: 0,
      );
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ThreadScreen(thread: thread, readOnly: true)));
    } else if (choice == 'resolve') {
      var close = false;
      final ok = await showFormSheet(
        context,
        title: 'Resolve report',
        submitLabel: 'Resolve',
        fields: const [
          FieldSpec('note', 'What did you decide? (optional)', kind: FieldKind.multiline),
          FieldSpec('close', 'Close this conversation (nobody can write in it again)', kind: FieldKind.toggle),
        ],
        onSubmit: (v) async {
          close = v['close'] == 'true';
          try {
            await repo.resolveReport(r.id, v['note']!.isEmpty ? null : v['note'], close);
          } catch (e) {
            throw FormError(friendlyError(e));
          }
        },
      );
      if (ok == true) {
        if (mounted) notify(context, close ? 'Resolved and conversation closed.' : 'Report resolved.');
        setState(() => _refresh++);
      }
    } else if (choice == 'mute') {
      final ok = await showFormSheet(
        context,
        title: 'Mute ${r.senderName}',
        subtitle: 'They will not be able to send any messages until you unmute them.',
        submitLabel: 'Mute',
        fields: const [FieldSpec('reason', 'Reason (optional)')],
        onSubmit: (v) async {
          try {
            await repo.setBlock(widget.school.id, r.senderId, true, v['reason']!.isEmpty ? null : v['reason']);
          } catch (e) {
            throw FormError(friendlyError(e));
          }
        },
      );
      if (ok == true) {
        if (mounted) notify(context, '${r.senderName} is muted.');
        setState(() => _refresh++);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Message moderation'),
          actions: const [
            HelpButton(
              title: 'Message moderation',
              steps: [
                'Messages between parents and teachers are private. You cannot browse them.',
                'When someone reports a message, it appears under "Reports". You can then read that conversation.',
                'Resolve the report, close the conversation, or mute the person who misused messaging.',
                'You can switch all messaging off at the top.',
              ],
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Reports'), Tab(text: 'Muted people')]),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow parent-teacher messages'),
                subtitle: Text(_enabled == false ? 'Messaging is switched off.' : 'Messaging is on.'),
                value: _enabled ?? true,
                onChanged: _enabled == null ? null : _toggle,
              ),
            ),
          ),
          Expanded(
            child: TabBarView(children: [
              AsyncList<MessageReportRow>(
                key: ValueKey('rep-$_refresh'),
                load: () => MessagingRepository.instance.reports(widget.school.id, 'open'),
                emptyIcon: Icons.verified_user_outlined,
                emptyTitle: 'No reports',
                emptyMessage: 'When a parent or teacher reports a message, it shows up here.',
                itemBuilder: (_, r, __) => AppCard(
                  onTap: () => _open(r),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r.senderName}  ->  about ${r.studentName}',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(r.messageBody, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text('Reported by ${r.reporterName}  ·  ${formatDate(r.createdAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
              AsyncList<BlockedUser>(
                key: ValueKey('blk-$_refresh'),
                load: () => MessagingRepository.instance.blocked(widget.school.id),
                emptyIcon: Icons.person_off_outlined,
                emptyTitle: 'Nobody is muted',
                emptyMessage: 'People you mute cannot send messages until you unmute them.',
                itemBuilder: (ctx, b, reload) => AppCard(
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        if ((b.reason ?? '').isNotEmpty)
                          Text(b.reason!, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ]),
                    ),
                    TextButton(
                      onPressed: () async {
                        try {
                          await MessagingRepository.instance.setBlock(widget.school.id, b.userId, false, null);
                          await reload();
                        } catch (e) {
                          if (ctx.mounted) notify(ctx, friendlyError(e), error: true);
                        }
                      },
                      child: const Text('Unmute'),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
