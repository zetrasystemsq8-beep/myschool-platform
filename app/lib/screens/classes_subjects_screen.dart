import 'package:flutter/material.dart';

import '../data/school.dart';
import '../data/school_repository.dart';
import '../data/setup_repository.dart';
import '../widgets/app_card.dart';
import '../widgets/async_list.dart';
import '../widgets/form_sheet.dart';

class ClassesSubjectsScreen extends StatelessWidget {
  const ClassesSubjectsScreen({super.key, required this.school});

  final School school;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Classes & subjects'),
          bottom: const TabBar(tabs: [Tab(text: 'Classes'), Tab(text: 'Subjects')]),
        ),
        body: TabBarView(children: [
          AsyncList<ClassRow>(
            load: () => SetupRepository.instance.classes(school.id),
            emptyIcon: Icons.class_outlined,
            emptyTitle: 'No classes yet',
            emptyMessage: 'Add classes such as "JSS 1 A".',
            addLabel: 'New class',
            onAdd: () => showFormSheet(
              context,
              title: 'New class',
              submitLabel: 'Create class',
              fields: const [
                FieldSpec('name', 'Class name', required: true, hint: 'JSS 1 A'),
                FieldSpec('level', 'Level (optional)', hint: 'JSS 1'),
              ],
              onSubmit: (v) async {
                try {
                  await SetupRepository.instance
                      .addClass(school.id, v['name']!, v['level']!.isEmpty ? null : v['level']);
                } catch (e) {
                  throw FormError(friendlyError(e));
                }
              },
            ),
            itemBuilder: (_, c, __) => AppCard(
              child: Row(children: [
                Icon(Icons.class_outlined, color: cs.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if ((c.level ?? '').isNotEmpty)
                      Text(c.level!, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
              ]),
            ),
          ),
          AsyncList<SubjectRow>(
            load: () => SetupRepository.instance.subjects(school.id),
            emptyIcon: Icons.menu_book_outlined,
            emptyTitle: 'No subjects yet',
            emptyMessage: 'Add subjects such as Mathematics.',
            addLabel: 'New subject',
            onAdd: () => showFormSheet(
              context,
              title: 'New subject',
              submitLabel: 'Create subject',
              fields: const [
                FieldSpec('name', 'Subject name', required: true, hint: 'Mathematics'),
                FieldSpec('code', 'Short code', required: true, hint: 'MTH'),
              ],
              onSubmit: (v) async {
                try {
                  await SetupRepository.instance.addSubject(school.id, v['name']!, v['code']!.toUpperCase());
                } catch (e) {
                  throw FormError(friendlyError(e));
                }
              },
            ),
            itemBuilder: (_, s, __) => AppCard(
              child: Row(children: [
                CircleAvatar(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  child: Text(s.code.length > 3 ? s.code.substring(0, 3) : s.code,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(s.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
