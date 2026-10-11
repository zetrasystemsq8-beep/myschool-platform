import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../data/setup_repository.dart';
import '../data/teacher_repository.dart';
import '../widgets/app_card.dart';
import '../widgets/async_list.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';

/// What a teacher teaches: class + subject + session. Result entry is limited to these.
class TeacherAssignmentsScreen extends StatelessWidget {
  const TeacherAssignmentsScreen({super.key, required this.school, required this.teacher});

  final School school;
  final MemberRow teacher;

  Future<bool?> _add(BuildContext context) async {
    final repo = SetupRepository.instance;
    try {
      final classes = await repo.classes(school.id);
      final subjects = await repo.subjects(school.id);
      final sessions = await repo.sessions(school.id);
      if (!context.mounted) return false;
      return showFormSheet(
        context,
        title: 'Assign to ${teacher.name}',
        submitLabel: 'Assign',
        fields: [
          FieldSpec('class', 'Class', kind: FieldKind.choice, required: true, options: [for (final c in classes) (c.id, c.name)]),
          FieldSpec('subject', 'Subject', kind: FieldKind.choice, required: true, options: [for (final s in subjects) (s.id, s.name)]),
          FieldSpec('session', 'Session', kind: FieldKind.choice, required: true, options: [for (final s in sessions) (s.id, s.name)]),
        ],
        onSubmit: (v) async {
          try {
            await repo.addAssignment(school.id, teacher.userId, v['class']!, v['subject']!, v['session']!);
          } catch (e) {
            throw FormError(e.toString().contains('23505')
                ? 'This teacher already has that class and subject for the session.'
                : friendlyError(e));
          }
        },
      );
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
      appBar: AppBar(title: Text(teacher.name)),
      body: AsyncList<Assignment>(
        load: () => TeacherRepository.instance.assignments(teacher.userId, school.id),
        emptyIcon: Icons.assignment_ind_outlined,
        emptyTitle: 'Nothing assigned yet',
        emptyMessage: 'Assign a class and subject so this teacher can enter results.',
        addLabel: 'Assign',
        onAdd: () => _add(context),
        itemBuilder: (ctx, a, reload) => AppCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.subjectName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text('${a.className}  ·  ${a.sessionName}',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            IconButton(
              tooltip: 'Remove',
              icon: Icon(Icons.delete_outline, color: cs.error),
              onPressed: () async {
                final ok = await confirmDialog(ctx,
                    title: 'Remove assignment?',
                    message: '${teacher.name} will no longer be able to enter ${a.subjectName} results for ${a.className}.',
                    action: 'Remove',
                    destructive: true);
                if (!ok) return;
                try {
                  await SetupRepository.instance.deleteAssignment(a.id);
                  await reload();
                } catch (e) {
                  if (ctx.mounted) notify(ctx, friendlyError(e), error: true);
                }
              },
            ),
          ]),
        ),
      ),
    );
  }
}
