import 'package:flutter/material.dart';

import '../data/admin_repository.dart';
import '../data/models.dart';
import '../data/portal_repository.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../data/setup_repository.dart';
import '../data/teacher_repository.dart';
import '../data/auth_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/help.dart';
import '../widgets/state_views.dart';

/// First tab for everyone: a greeting, what needs attention, and the next step.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.school,
    required this.member,
    required this.student,
    required this.active,
    required this.onGoTo,
  });

  final School school;
  final Member member;
  final StudentInfo? student;
  final bool active; // true while this tab is showing (refreshes numbers when you come back)
  final void Function(String tabId) onGoTo;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  String? _error;
  String _name = '';

  // student / parent
  TermGroup? _latest;
  List<Announcement> _news = const [];
  // teacher
  int _classes = 0, _inProgress = 0, _waiting = 0, _sentBack = 0;
  // admin
  int _toApprove = 0, _toShare = 0;
  List<(String, bool)> _checklist = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load(quiet: true);
    if (widget.student?.id != old.student?.id) _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() { _loading = true; _error = null; });
    try {
      final m = widget.member;
      final uid = AuthRepository.instance.userId!;
      final portal = PortalRepository.instance;
      String name = widget.student?.firstName ?? '';
      if (name.isEmpty) {
        final full = await portal.fullName(uid);
        name = (full ?? '').trim().split(' ').first;
      }

      if (m.hasStudentView) {
        final student = widget.student;
        final rows = student == null ? <ResultRow>[] : await portal.results(student.id);
        final groups = groupResults(rows);
        final news = await portal.announcements(widget.school.id);
        if (!mounted) return;
        setState(() {
          _latest = groups.isEmpty ? null : groups.first;
          _news = news.take(2).toList();
        });
      } else if (m.role == 'teacher') {
        final repo = TeacherRepository.instance;
        final items = await repo.assignments(uid, widget.school.id);
        final o = await repo.overview(widget.school.id);
        if (!mounted) return;
        setState(() {
          _classes = items.length;
          _inProgress = o.inProgress;
          _waiting = o.waiting;
          _sentBack = o.sentBack;
        });
      } else if (m.role == 'school_admin') {
        final counts = await AdminRepository.instance.sheetCounts(widget.school.id);
        final setup = SetupRepository.instance;
        final id = widget.school.id;
        final sessions = await setup.sessions(id);
        final classes = await setup.classes(id);
        final subjects = await setup.subjects(id);
        final teachers = await setup.members(id, 'teacher');
        final students = await setup.students(id);
        if (!mounted) return;
        setState(() {
          _toApprove = counts['submitted'] ?? 0;
          _toShare = counts['approved'] ?? 0;
          _checklist = [
            ('Add the current school year', sessions.isNotEmpty),
            ('Add its terms (First, Second, Third)', sessions.any((s) => s.terms.isNotEmpty)),
            ('Add your classes', classes.isNotEmpty),
            ('Add your subjects', subjects.isNotEmpty),
            ('Add your teachers', teachers.isNotEmpty),
            ('Add your students', students.isNotEmpty),
          ];
        });
      }
      if (!mounted) return;
      setState(() {
        _name = name;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!quiet) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    final part = h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
    return _name.isEmpty ? part : '$part, $_name';
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.green, AppTheme.greenLight],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_greeting,
            style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('${widget.school.name}  ·  ${widget.member.roleLabel}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
      ]),
    );
  }

  Widget _stat(String label, int value, {VoidCallback? onTap, Color? color}) {
    final theme = Theme.of(context);
    return Expanded(
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value',
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold, color: color ?? theme.colorScheme.primary)),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- student / parent

  List<Widget> _studentBody() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (widget.student == null) {
      return const [
        HintBanner(
          icon: Icons.person_search_outlined,
          text: 'No student is linked to this account yet. Please contact your school.',
        ),
      ];
    }
    final l = _latest;
    return [
      SectionTitle('Latest results', action: 'See all', onAction: () => widget.onGoTo('results')),
      if (l == null)
        AppCard(
          child: Row(children: [
            Icon(Icons.hourglass_empty, color: cs.primary),
            const SizedBox(width: 12),
            const Expanded(child: Text('Your results will appear here as soon as your school shares them.')),
          ]),
        )
      else
        AppCard(
          onTap: () => widget.onGoTo('results'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${l.className}  ·  ${l.label}',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Row(children: [
              _big('Average', fmt(l.average)),
              _big('Subjects', '${l.rows.length}'),
              _big('Total', fmt(l.totalScore)),
            ]),
          ]),
        ),
      const SizedBox(height: 8),
      SectionTitle('Latest notices', action: 'See all', onAction: () => widget.onGoTo('notices')),
      if (_news.isEmpty)
        const AppCard(child: Text('No notices from your school yet.'))
      else
        for (final n in _news) ...[
          AppCard(
            onTap: () => widget.onGoTo('notices'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(formatDate(n.publishedAt),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(height: 10),
        ],
    ];
  }

  Widget _big(String label, String value) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }

  // ---------------------------------------------------------------- teacher

  List<Widget> _teacherBody() {
    return [
      Row(children: [
        _stat('Classes I teach', _classes, onTap: () => widget.onGoTo('classes')),
        const SizedBox(width: 10),
        _stat('In progress', _inProgress, onTap: () => widget.onGoTo('classes')),
        const SizedBox(width: 10),
        _stat('Waiting for approval', _waiting, onTap: () => widget.onGoTo('classes')),
      ]),
      const SizedBox(height: 14),
      if (_sentBack > 0) ...[
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.onGoTo('classes'),
          child: HintBanner(
            icon: Icons.reply,
            text: _sentBack == 1
                ? '1 set of results was sent back to you for changes. Tap to open Classes.'
                : '$_sentBack sets of results were sent back to you for changes. Tap to open Classes.',
          ),
        ),
        const SizedBox(height: 14),
      ],
      if (_classes == 0)
        const HintBanner(
          text: 'Your administrator has not chosen your classes yet. Once they do, they appear under Classes.',
        )
      else
        FilledButton.icon(
          onPressed: () => widget.onGoTo('classes'),
          icon: const Icon(Icons.edit_note),
          label: const Text('Enter results'),
        ),
      const SizedBox(height: 14),
      const HintBanner(
        icon: Icons.tips_and_updates_outlined,
        text: 'How it works: open Classes, pick a class and a term, type each student\'s scores, then tap "Send for approval".',
      ),
    ];
  }

  // ---------------------------------------------------------------- admin

  List<Widget> _adminBody() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final done = _checklist.where((c) => c.$2).length;
    final ready = _checklist.isNotEmpty && done == _checklist.length;
    return [
      Row(children: [
        _stat('Waiting for your approval', _toApprove,
            color: _toApprove > 0 ? const Color(0xFFE07B00) : null, onTap: () => widget.onGoTo('review')),
        const SizedBox(width: 10),
        _stat('Approved, not shared yet', _toShare, onTap: () => widget.onGoTo('review')),
      ]),
      const SizedBox(height: 18),
      if (!ready) ...[
        SectionTitle('Get your school ready'),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$done of ${_checklist.length} steps done',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _checklist.isEmpty ? 0 : done / _checklist.length,
                minHeight: 8,
                color: AppTheme.green,
                backgroundColor: AppTheme.green.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 10),
            for (final c in _checklist)
              InkWell(
                onTap: () => widget.onGoTo('setup'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Icon(c.$2 ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: c.$2 ? AppTheme.green : cs.onSurfaceVariant, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(c.$1,
                          style: TextStyle(
                            decoration: c.$2 ? TextDecoration.lineThrough : null,
                            color: c.$2 ? cs.onSurfaceVariant : null,
                          )),
                    ),
                    if (!c.$2) Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => widget.onGoTo('setup'),
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Go to My school'),
        ),
      ] else
        const HintBanner(
          icon: Icons.check_circle_outline,
          text: 'Your school is set up. Teachers can enter results, and you approve them under Approvals.',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return MessageView(
          icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load);
    }
    final body = widget.member.hasStudentView
        ? _studentBody()
        : (widget.member.role == 'teacher' ? _teacherBody() : _adminBody());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
          ),
        ],
      ),
    );
  }
}
