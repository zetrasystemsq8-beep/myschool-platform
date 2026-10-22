import 'package:flutter/material.dart';

import '../widgets/help.dart';

import '../data/school.dart';
import '../data/school_repository.dart';
import '../data/setup_repository.dart';
import '../widgets/app_card.dart';
import '../widgets/async_list.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';
import '../data/models.dart';
import '../data/portal_repository.dart';
import '../data/report_card_pdf.dart';
import 'teacher_assignments_screen.dart';

final _pinRe = RegExp(r'^[A-Za-z0-9]{6,32}$');
final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Students, teachers and parents of the school (account creation uses the
/// myschool-provision-user Edge Function, because it needs the service role).
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key, required this.school});

  final School school;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('People'),
          actions: const [
            HelpButton(
              title: 'People',
              steps: [
                'Students: tap "Add student". They sign in with their admission number and the PIN you set.',
                'Teachers: tap "Add teacher", then tap the teacher to choose the classes and subjects they teach.',
                'Parents: tap "Add parent" and choose their child. They sign in with their email.',
                'Someone forgot their PIN or password? Tap their name (students) or the ⋮ menu (others) to set a new one.',
              ],
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Students'), Tab(text: 'Teachers'), Tab(text: 'Parents')]),
        ),
        body: TabBarView(children: [
          _StudentsTab(school: school),
          _TeachersTab(school: school),
          _ParentsTab(school: school),
        ]),
      ),
    );
  }
}

/// Admin sets a new password for a teacher or parent who forgot theirs.
Future<void> _resetStaffPassword(BuildContext context, School school, MemberRow m) async {
  final ok = await showFormSheet(
    context,
    title: 'Reset password',
    subtitle: m.name,
    submitLabel: 'Set new password',
    fields: const [FieldSpec('pw', 'New password (at least 10 characters)', kind: FieldKind.password, required: true)],
    onSubmit: (v) async {
      if (v['pw']!.length < 10) throw FormError('The password must be at least 10 characters.');
      try {
        await SetupRepository.instance.provision({
          'action': 'reset_password',
          'school_id': school.id,
          'user_id': m.userId,
          'new_password': v['pw'],
        });
      } catch (e) {
        throw FormError(provisionError(e));
      }
    },
  );
  if (ok == true && context.mounted) notify(context, 'Password updated. Share it with them privately.');
}

// ------------------------------------------------------------------ students

class _StudentsTab extends StatelessWidget {
  const _StudentsTab({required this.school});

  final School school;

  Future<bool?> _add(BuildContext context) async {
    final repo = SetupRepository.instance;
    try {
      final classes = await repo.classes(school.id);
      final sessions = await repo.sessions(school.id);
      if (!context.mounted) return false;
      return showFormSheet(
        context,
        title: 'Add student',
        subtitle: 'The student signs in with the admission number and this PIN.',
        submitLabel: 'Create student',
        fields: [
          const FieldSpec('adm', 'Admission number', required: true, hint: '2025/017'),
          const FieldSpec('first', 'First name', required: true),
          const FieldSpec('last', 'Last name', required: true),
          const FieldSpec('pin', 'PIN (6-32 letters or digits)', kind: FieldKind.password, required: true),
          FieldSpec('class', 'Class (optional)',
              kind: FieldKind.choice, options: [for (final c in classes) (c.id, c.name)]),
          FieldSpec('session', 'School year (default: current)',
              kind: FieldKind.choice, options: [for (final s in sessions) (s.id, s.name)]),
        ],
        onSubmit: (v) async {
          if (!_pinRe.hasMatch(v['pin']!)) {
            throw FormError('The PIN must be 6 to 32 letters or digits, with no spaces.');
          }
          var session = v['session']!;
          final classId = v['class']!;
          if (classId.isNotEmpty && session.isEmpty) {
            session = await repo.currentSessionId(school.id) ?? '';
            if (session.isEmpty) {
              throw FormError('There is no current school year. Choose one, or add a school year first.');
            }
          }
          try {
            await repo.provision({
              'action': 'create',
              'school_id': school.id,
              'role': 'student',
              'student': {
                'admission_number': v['adm'],
                'first_name': v['first'],
                'last_name': v['last'],
                'pin': v['pin'],
                if (classId.isNotEmpty) 'class_id': classId,
                if (classId.isNotEmpty) 'session_id': session,
              },
            });
          } catch (e) {
            throw FormError(provisionError(e));
          }
        },
      );
    } catch (e) {
      if (context.mounted) notify(context, friendlyError(e), error: true);
      return false;
    }
  }

  Future<void> _enroll(BuildContext context, StudentRow s, Future<void> Function() reload) async {
    final repo = SetupRepository.instance;
    try {
      final classes = await repo.classes(school.id);
      final sessions = await repo.sessions(school.id);
      if (!context.mounted) return;
      final saved = await showFormSheet(
        context,
        title: 'Put ${s.name} in a class',
        submitLabel: 'Save',
        fields: [
          FieldSpec('class', 'Class', kind: FieldKind.choice, required: true, options: [for (final c in classes) (c.id, c.name)]),
          FieldSpec('session', 'School year', kind: FieldKind.choice, required: true, options: [for (final x in sessions) (x.id, x.name)]),
        ],
        onSubmit: (v) async {
          try {
            await repo.enroll(school.id, s.id, v['class']!, v['session']!);
          } catch (e) {
            throw FormError(e.toString().contains('23505')
                ? 'This student already has a class for that school year.'
                : friendlyError(e));
          }
        },
      );
      if (saved == true) await reload();
    } catch (e) {
      if (context.mounted) notify(context, friendlyError(e), error: true);
    }
  }

  Future<void> _resetPin(BuildContext context, StudentRow s) async {
    await showFormSheet(
      context,
      title: 'Reset PIN',
      subtitle: s.name,
      submitLabel: 'Set new PIN',
      fields: const [FieldSpec('pin', 'New PIN', kind: FieldKind.password, required: true)],
      onSubmit: (v) async {
        if (!_pinRe.hasMatch(v['pin']!)) {
          throw FormError('The PIN must be 6 to 32 letters or digits, with no spaces.');
        }
        try {
          await SetupRepository.instance.provision({
            'action': 'reset_password',
            'school_id': school.id,
            'user_id': s.userId,
            'new_password': v['pin'],
          });
        } catch (e) {
          throw FormError(provisionError(e));
        }
      },
    ).then((ok) {
      if (ok == true && context.mounted) notify(context, 'PIN updated.');
    });
  }

  Future<void> _reportCard(BuildContext context, StudentRow s) async {
    try {
      final groups = groupResults(await PortalRepository.instance.results(s.id));
      if (groups.isEmpty) {
        if (context.mounted) notify(context, 'No shared results for ${s.name} yet.', error: true);
        return;
      }
      var chosen = groups.first;
      if (groups.length > 1 && context.mounted) {
        final picked = await showModalBottomSheet<TermGroup>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Which term?', style: Theme.of(ctx).textTheme.titleMedium),
                ),
              ),
              for (final g in groups)
                ListTile(title: Text(g.label), subtitle: Text(g.className), onTap: () => Navigator.pop(ctx, g)),
              const SizedBox(height: 8),
            ]),
          ),
        );
        if (picked == null) return;
        chosen = picked;
      }
      final scale = await PortalRepository.instance.gradingScale(school.id);
      await printReportCard(
        schoolName: school.name,
        studentName: s.name,
        admissionNumber: s.admissionNumber,
        term: chosen,
        scale: scale,
      );
    } catch (e) {
      if (context.mounted) notify(context, friendlyError(e), error: true);
    }
  }

  Future<void> _changeStatus(BuildContext context, StudentRow s, Future<void> Function() reload) async {
    final ok = await showFormSheet(
      context,
      title: 'Change status',
      subtitle: s.name,
      submitLabel: 'Save',
      fields: [
        FieldSpec('status', 'Status', kind: FieldKind.choice, required: true, initial: s.status, options: const [
          ('active', 'Active'),
          ('graduated', 'Graduated (can still see old results)'),
          ('withdrawn', 'Withdrawn (left the school)'),
          ('transferred', 'Transferred to another school'),
          ('suspended', 'Suspended (cannot sign in)'),
        ]),
        const FieldSpec('reason', 'Reason (optional)'),
      ],
      onSubmit: (v) async {
        try {
          await SetupRepository.instance.setStudentStatus(s.id, v['status']!, v['reason']!.isEmpty ? null : v['reason']);
        } catch (e) {
          throw FormError(friendlyError(e));
        }
      },
    );
    if (ok == true) {
      if (context.mounted) notify(context, 'Status updated for ${s.name}.');
      await reload();
    }
  }

  Future<void> _actions(BuildContext context, StudentRow s, Future<void> Function() reload) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(s.name, style: Theme.of(ctx).textTheme.titleMedium),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.how_to_reg_outlined),
            title: const Text('Put in a class'),
            onTap: () => Navigator.pop(ctx, 'enroll'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Report card'),
            onTap: () => Navigator.pop(ctx, 'card'),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Change status (graduated, left the school ...)'),
            onTap: () => Navigator.pop(ctx, 'status'),
          ),
          if (s.userId != null)
            ListTile(
              leading: const Icon(Icons.lock_reset),
              title: const Text('Reset PIN'),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'enroll') await _enroll(context, s, reload);
    if (choice == 'pin') await _resetPin(context, s);
    if (choice == 'card') await _reportCard(context, s);
    if (choice == 'status') await _changeStatus(context, s, reload);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AsyncList<StudentRow>(
      load: () => SetupRepository.instance.students(school.id),
      emptyIcon: Icons.school_outlined,
      emptyTitle: 'No students yet',
      emptyMessage: 'Add your students here. It is easier if you have already added the school year and classes.',
      addLabel: 'Add student',
      onAdd: () => _add(context),
      itemBuilder: (ctx, s, reload) => AppCard(
        onTap: () => _actions(ctx, s, reload),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(s.admissionNumber, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          if (s.status != 'active') StatusPill(label: s.status, color: const Color(0xFFE07B00)),
          Icon(Icons.more_vert, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ teachers

class _TeachersTab extends StatelessWidget {
  const _TeachersTab({required this.school});

  final School school;

  Future<bool?> _add(BuildContext context) {
    return showFormSheet(
      context,
      title: 'Add teacher',
      subtitle: 'The teacher signs in with this email and password.',
      submitLabel: 'Create teacher',
      fields: const [
        FieldSpec('name', 'Full name', required: true),
        FieldSpec('email', 'Email', required: true, keyboard: TextInputType.emailAddress),
        FieldSpec('password', 'Password (at least 10 characters)', kind: FieldKind.password, required: true),
        FieldSpec('staff', 'Staff number (optional)'),
      ],
      onSubmit: (v) async {
        if (!_emailRe.hasMatch(v['email']!)) throw FormError('Please enter a valid email address.');
        if (v['password']!.length < 10) throw FormError('The password must be at least 10 characters.');
        try {
          await SetupRepository.instance.provision({
            'action': 'create',
            'school_id': school.id,
            'role': 'teacher',
            'full_name': v['name'],
            'email': v['email'],
            'password': v['password'],
            if (v['staff']!.isNotEmpty) 'staff_number': v['staff'],
          });
        } catch (e) {
          throw FormError(provisionError(e));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AsyncList<MemberRow>(
      load: () => SetupRepository.instance.members(school.id, 'teacher'),
      emptyIcon: Icons.person_outline,
      emptyTitle: 'No teachers yet',
      emptyMessage: 'Add a teacher, then choose which classes and subjects they teach.',
      addLabel: 'Add teacher',
      onAdd: () => _add(context),
      itemBuilder: (ctx, t, reload) => AppCard(
        onTap: () => Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => TeacherAssignmentsScreen(school: school, teacher: t),
        )),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            child: Text(t.name.isEmpty ? '?' : t.name[0].toUpperCase()),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text('Tap to choose what they teach',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          PopupMenuButton<String>(
            onSelected: (_) => _resetStaffPassword(ctx, school, t),
            itemBuilder: (_) => const [PopupMenuItem(value: 'pw', child: Text('Reset password'))],
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ parents

class _ParentsTab extends StatelessWidget {
  const _ParentsTab({required this.school});

  final School school;

  Future<bool?> _add(BuildContext context) async {
    try {
      final students = await SetupRepository.instance.students(school.id);
      if (!context.mounted) return false;
      return showFormSheet(
        context,
        title: 'Add parent',
        subtitle: 'The parent signs in with this email and sees their child\'s published results.',
        submitLabel: 'Create parent',
        fields: [
          const FieldSpec('name', 'Full name', required: true),
          const FieldSpec('email', 'Email', required: true, keyboard: TextInputType.emailAddress),
          const FieldSpec('password', 'Password (at least 10 characters)', kind: FieldKind.password, required: true),
          FieldSpec('student', 'Child', kind: FieldKind.choice, required: true,
              options: [for (final s in students) (s.id, '${s.name} (${s.admissionNumber})')]),
        ],
        onSubmit: (v) async {
          if (!_emailRe.hasMatch(v['email']!)) throw FormError('Please enter a valid email address.');
          if (v['password']!.length < 10) throw FormError('The password must be at least 10 characters.');
          try {
            await SetupRepository.instance.provision({
              'action': 'create',
              'school_id': school.id,
              'role': 'parent',
              'full_name': v['name'],
              'email': v['email'],
              'password': v['password'],
              'link_student_ids': [v['student']],
            });
          } catch (e) {
            throw FormError(provisionError(e));
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
    return AsyncList<MemberRow>(
      load: () => SetupRepository.instance.members(school.id, 'parent'),
      emptyIcon: Icons.family_restroom,
      emptyTitle: 'No parents yet',
      emptyMessage: 'Add a parent and link them to their child.',
      addLabel: 'Add parent',
      onAdd: () => _add(context),
      itemBuilder: (ctx, p, __) => AppCard(
        child: Row(children: [
          CircleAvatar(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase()),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(p.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          PopupMenuButton<String>(
            onSelected: (_) => _resetStaffPassword(ctx, school, p),
            itemBuilder: (_) => const [PopupMenuItem(value: 'pw', child: Text('Reset password'))],
          ),
        ]),
      ),
    );
  }
}
