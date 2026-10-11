import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/auth_repository.dart';
import '../data/models.dart';
import '../data/portal_repository.dart';
import '../data/school.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';
import '../widgets/school_avatar.dart';
import 'school_home_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.school,
    required this.member,
    required this.student,
  });

  final School school;
  final Member member;
  final StudentInfo? student;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _name;
  String? _classLabel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = PortalRepository.instance;
    try {
      final uid = AuthRepository.instance.userId;
      final name = uid == null ? null : await repo.fullName(uid);
      final label = widget.student == null
          ? null
          : await repo.enrollmentLabel(widget.student!.id);
      if (!mounted) return;
      setState(() {
        _name = name;
        _classLabel = label;
      });
    } catch (_) {
      // Profile details are optional; the page still works without them.
    }
  }

  Future<void> _changePassword() async {
    final isStudent = widget.member.isStudent;
    final label = isStudent ? 'PIN' : 'password';
    final ok = await showFormSheet(
      context,
      title: 'Change $label',
      submitLabel: 'Save new $label',
      fields: [
        FieldSpec('new', 'New $label', kind: FieldKind.password, required: true),
        FieldSpec('again', 'Repeat new $label', kind: FieldKind.password, required: true),
      ],
      onSubmit: (v) async {
        final value = v['new']!;
        if (value != v['again']) throw FormError('The two entries do not match.');
        if (isStudent && !RegExp(r'^[A-Za-z0-9]{6,32}$').hasMatch(value)) {
          throw FormError('The PIN must be 6 to 32 letters or digits, with no spaces.');
        }
        if (!isStudent && value.length < 10) {
          throw FormError('The password must be at least 10 characters.');
        }
        try {
          await AuthRepository.instance.changePassword(value);
        } catch (e) {
          throw FormError(authError(e));
        }
      },
    );
    if (ok == true && mounted) notify(context, 'Your $label was changed.');
  }

  Future<void> _signOut() async {
    await AuthRepository.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SchoolHomeScreen(school: widget.school)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final student = widget.student;
    final display = student?.fullName ?? _name ?? AuthRepository.instance.email ?? 'Signed in';
    final initial = display.trim().isEmpty ? '?' : display.trim()[0].toUpperCase();

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                  Text(value, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: AppTheme.green,
            child: Text(initial,
                style: const TextStyle(
                    color: AppTheme.gold,
                    fontSize: 32,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 14),
        Text(display,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Center(
          child: Chip(
            label: Text(widget.member.roleLabel),
            backgroundColor: AppTheme.gold.withValues(alpha: 0.2),
            side: BorderSide.none,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              if (student != null) ...[
                row(Icons.badge_outlined, 'Admission number', student.admissionNumber),
                if (_classLabel != null)
                  row(Icons.class_outlined, 'Class', _classLabel!),
              ],
              if (AuthRepository.instance.email != null &&
                  !AuthRepository.instance.email!.endsWith('.local'))
                row(Icons.email_outlined, 'Email', AuthRepository.instance.email!),
              Row(children: [
                SchoolAvatar(school: widget.school, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.school.name,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Appearance',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: AppSettings.themeMode,
              builder: (_, mode, __) => SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {mode},
                onSelectionChanged: (s) => AppSettings.setThemeMode(s.first),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _changePassword,
          icon: const Icon(Icons.key_outlined),
          label: Text(widget.member.isStudent ? 'Change PIN' : 'Change password'),
        ),
        if (widget.member.isStaff) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
                widget.member.role == 'teacher'
                ? 'Enter and submit results from the Classes tab.'
                : 'Approve results in Review, and manage the school in Setup.'),
          ),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
