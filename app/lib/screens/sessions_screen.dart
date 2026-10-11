import 'package:flutter/material.dart';

import '../data/school.dart';
import '../data/school_repository.dart';
import '../data/setup_repository.dart';
import '../widgets/app_card.dart';
import '../widgets/async_list.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';
import '../theme/app_theme.dart';

class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key, required this.school});

  final School school;

  Future<bool?> _addSession(BuildContext context) {
    return showFormSheet(
      context,
      title: 'New session',
      subtitle: 'An academic year, e.g. 2025/2026.',
      submitLabel: 'Create session',
      fields: const [
        FieldSpec('name', 'Session name', required: true, hint: '2025/2026'),
        FieldSpec('start', 'Start date', kind: FieldKind.date, required: true),
        FieldSpec('end', 'End date', kind: FieldKind.date, required: true),
        FieldSpec('current', 'Make this the current session', kind: FieldKind.toggle),
      ],
      onSubmit: (v) async {
        if (v['end']!.compareTo(v['start']!) <= 0) {
          throw FormError('The end date must be after the start date.');
        }
        try {
          await SetupRepository.instance
              .addSession(school.id, v['name']!, v['start']!, v['end']!, v['current'] == 'true');
        } catch (e) {
          throw FormError(friendlyError(e));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sessions & terms')),
      body: AsyncList<SessionInfo>(
        load: () => SetupRepository.instance.sessions(school.id),
        emptyIcon: Icons.event_note_outlined,
        emptyTitle: 'No sessions yet',
        emptyMessage: 'Create the first academic session, then add its terms.',
        addLabel: 'New session',
        onAdd: () => _addSession(context),
        itemBuilder: (ctx, s, reload) => _SessionCard(school: school, session: s, reload: reload),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.school, required this.session, required this.reload});

  final School school;
  final SessionInfo session;
  final Future<void> Function() reload;

  Future<void> _addTerm(BuildContext context) async {
    final used = session.terms.map((t) => t.number).toSet();
    final options = [
      for (var n = 1; n <= 4; n++)
        if (!used.contains(n)) ('$n', 'Term $n'),
    ];
    if (options.isEmpty) {
      notify(context, 'This session already has all four terms.', error: true);
      return;
    }
    final saved = await showFormSheet(
      context,
      title: 'Add term',
      subtitle: session.name,
      submitLabel: 'Add term',
      fields: [
        FieldSpec('number', 'Term number', kind: FieldKind.choice, required: true, options: options),
        const FieldSpec('name', 'Term name', required: true, hint: 'First Term'),
      ],
      onSubmit: (v) async {
        try {
          await SetupRepository.instance
              .addTerm(school.id, session.id, int.parse(v['number']!), v['name']!);
        } catch (e) {
          throw FormError(friendlyError(e));
        }
      },
    );
    if (saved == true) await reload();
  }

  Future<void> _makeCurrent(BuildContext context, {String? termId}) async {
    try {
      if (termId == null) {
        await SetupRepository.instance.setCurrentSession(school.id, session.id);
      } else {
        await SetupRepository.instance.setCurrentTerm(school.id, termId);
      }
      await reload();
    } catch (e) {
      if (context.mounted) notify(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(session.name,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (session.isCurrent) const StatusPill(label: 'Current', color: AppTheme.green),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'term' ? _addTerm(context) : _makeCurrent(context),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'term', child: Text('Add a term')),
              if (!session.isCurrent) const PopupMenuItem(value: 'current', child: Text('Make current')),
            ],
          ),
        ]),
        Text('${session.start}  →  ${session.end}',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        if (session.terms.isEmpty)
          Text('No terms yet. Use the menu to add one.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        for (final t in session.terms)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Icon(Icons.subdirectory_arrow_right, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(child: Text('${t.name}  (term ${t.number})')),
              if (t.isCurrent)
                const StatusPill(label: 'Current', color: AppTheme.gold)
              else
                TextButton(
                  onPressed: () => _makeCurrent(context, termId: t.id),
                  child: const Text('Make current'),
                ),
            ]),
          ),
      ]),
    );
  }
}
