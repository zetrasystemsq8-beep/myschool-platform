import 'package:flutter/material.dart';

import '../data/school.dart';
import '../widgets/app_card.dart';
import 'attendance_screen.dart';
import 'classes_subjects_screen.dart';
import 'people_screen.dart';
import 'sessions_screen.dart';

/// Administrator's setup area. Suggested order is shown by the numbers.
class SetupHubScreen extends StatelessWidget {
  const SetupHubScreen({super.key, required this.school});

  final School school;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget tile(int n, IconData icon, String title, String subtitle, Widget page) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                child: Icon(icon, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$n. $title',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ]),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('Get ${school.name} ready',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Do these three things in order. You can change them any time.',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),
        tile(1, Icons.event_note_outlined, 'School years & terms', 'The current year and its terms',
            SessionsScreen(school: school)),
        tile(2, Icons.class_outlined, 'Classes & subjects', 'The classes you have and what you teach',
            ClassesSubjectsScreen(school: school)),
        tile(3, Icons.groups_outlined, 'People', 'Add students, teachers and parents',
            PeopleScreen(school: school)),
        const SizedBox(height: 8),
        Text('Day to day', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        tile(4, Icons.event_available_outlined, 'Attendance', 'See and correct attendance for any class',
            Scaffold(
              appBar: AppBar(title: const Text('Attendance')),
              body: AttendanceScreen(school: school, isAdmin: true),
            )),
      ],
    );
  }
}
