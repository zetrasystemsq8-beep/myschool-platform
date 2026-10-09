import 'package:flutter/material.dart';

import '../data/school.dart';
import '../data/school_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/school_avatar.dart';
import 'school_search_screen.dart';

/// The school's own space. Slice 1 shows the public profile; sign-in comes next.
class SchoolHomeScreen extends StatefulWidget {
  const SchoolHomeScreen({super.key, required this.school});

  final School school;

  @override
  State<SchoolHomeScreen> createState() => _SchoolHomeScreenState();
}

class _SchoolHomeScreenState extends State<SchoolHomeScreen> {
  late School _school;

  @override
  void initState() {
    super.initState();
    _school = widget.school;
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final fresh = await SchoolRepository.instance.byCode(_school.code);
      if (fresh == null || !mounted) return;
      setState(() => _school = fresh);
      await SchoolRepository.instance.saveSchool(fresh);
    } catch (_) {
      // Offline or service unavailable: keep showing the saved profile.
    }
  }

  Future<void> _changeSchool() async {
    await SchoolRepository.instance.clearSavedSchool();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SchoolSearchScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final about = _school.description?.trim() ?? '';
    final website = _school.website?.trim() ?? '';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _Header(school: _school),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (about.isNotEmpty)
                    _InfoCard(
                        icon: Icons.info_outline, title: 'About', text: about),
                  if (website.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _InfoCard(
                        icon: Icons.language, title: 'Website', text: website),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () =>
                        ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Sign-in arrives in the next update.')),
                    ),
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _changeSchool,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Change school'),
                  ),
                  const SizedBox(height: 28),
                  Text('Powered by MySchool',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.school});

  final School school;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final motto = school.motto?.trim() ?? '';
    return Container(
      padding: EdgeInsets.fromLTRB(24, top + 32, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.green, AppTheme.greenLight],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
            ),
            child: SchoolAvatar(school: school, size: 84),
          ),
          const SizedBox(height: 18),
          Text(school.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          if (motto.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(motto,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.gold,
                    fontSize: 15,
                    fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(icon: Icons.tag, text: school.code),
              if (school.location.isNotEmpty)
                _Pill(icon: Icons.place_outlined, text: school.location),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: Colors.white),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            Text(text, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
