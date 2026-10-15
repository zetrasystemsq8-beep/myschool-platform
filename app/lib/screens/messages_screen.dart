import 'package:flutter/material.dart';

import '../data/messaging_repository.dart';
import '../data/models.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/async_list.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';
import '../widgets/help.dart';
import 'thread_screen.dart';

/// Parent <-> teacher messages (parents message their child's teachers; teachers reply or reach parents).
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key, required this.school, required this.isParent});

  final School school;
  final bool isParent;

  Future<bool?> _start(BuildContext context) async {
    try {
      final contacts = await MessagingRepository.instance.contacts(school.id);
      if (!context.mounted) return false;
      if (contacts.isEmpty) {
        notify(
          context,
          isParent
              ? 'No teacher can be messaged yet. Your child needs a class and teachers for the current school year.'
              : 'No parents can be messaged yet. Students you teach need a linked parent.',
          error: true,
        );
        return false;
      }
      var started = false;
      final ok = await showFormSheet(
        context,
        title: 'New message',
        subtitle: 'This is private between you and the person you choose.',
        submitLabel: 'Send',
        fields: [
          FieldSpec('who', isParent ? 'Teacher' : 'Parent', kind: FieldKind.choice, required: true, options: [
            for (var i = 0; i < contacts.length; i++)
              ('$i', '${contacts[i].otherName}  -  ${contacts[i].studentName}${contacts[i].detail.isEmpty ? '' : ' (${contacts[i].detail})'}'),
          ]),
          const FieldSpec('subject', 'Subject (optional)'),
          const FieldSpec('body', 'Message', kind: FieldKind.multiline, required: true),
        ],
        onSubmit: (v) async {
          final c = contacts[int.parse(v['who']!)];
          try {
            await MessagingRepository.instance.start(
              studentId: c.studentId,
              otherUserId: c.otherUserId,
              subject: v['subject']!.isEmpty ? null : v['subject'],
              body: v['body']!,
            );
            started = true;
          } catch (e) {
            throw FormError(friendlyError(e));
          }
        },
      );
      return ok == true && started;
    } catch (e) {
      if (context.mounted) notify(context, friendlyError(e), error: true);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: const [
          HelpButton(
            title: 'Messages',
            intro: 'Private messages between parents and their child\'s teachers.',
            steps: [
              'Tap "New message" and choose who to write to.',
              'Only a parent and a teacher of the same student can message each other.',
              'The school cannot read your conversations. They can only read one if someone reports it.',
              'Be polite. The school can mute anyone who misuses messages.',
            ],
          ),
        ],
      ),
      body: AsyncList<ThreadSummary>(
        load: () => MessagingRepository.instance.threads(school.id),
        emptyIcon: Icons.forum_outlined,
        emptyTitle: 'No messages yet',
        emptyMessage: 'Tap "New message" to write to a teacher or parent.',
        addLabel: 'New message',
        onAdd: () => _start(context),
        itemBuilder: (ctx, t, reload) => AppCard(
          onTap: () async {
            await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => ThreadScreen(thread: t)));
            await reload();
          },
          child: Row(children: [
            CircleAvatar(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              child: Text(t.otherName.isEmpty ? '?' : t.otherName[0].toUpperCase()),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.otherName,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: t.unread > 0 ? FontWeight.bold : FontWeight.w600)),
                Text('About ${t.studentName}${t.isClosed ? '  ·  closed' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                if ((t.lastBody ?? '').isNotEmpty)
                  Text(t.lastBody!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: t.unread > 0 ? FontWeight.w600 : FontWeight.normal)),
              ]),
            ),
            if (t.unread > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppTheme.gold, borderRadius: BorderRadius.circular(12)),
                child: Text('${t.unread}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
          ]),
        ),
      ),
    );
  }
}
