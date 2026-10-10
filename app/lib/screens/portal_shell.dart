import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/models.dart';
import '../data/portal_repository.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../widgets/state_views.dart';
import 'announcements_screen.dart';
import 'profile_screen.dart';
import 'results_screen.dart';
import 'teacher_home_screen.dart';

/// Signed-in area with bottom navigation.
/// Students/parents: Results, Announcements, Profile.  Staff: Announcements, Account
/// (teacher and admin tools arrive in later updates).
class PortalShell extends StatefulWidget {
  const PortalShell({super.key, required this.school, required this.member});

  final School school;
  final Member member;

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell> {
  List<StudentInfo> _students = const [];
  int _child = 0;
  int _tab = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = AuthRepository.instance.userId!;
      final repo = PortalRepository.instance;
      List<StudentInfo> list = const [];
      if (widget.member.isStudent) {
        final s = await repo.myStudentRecord(uid, widget.school.id);
        list = s == null ? const [] : [s];
      } else if (widget.member.isParent) {
        list = await repo.children(uid, widget.school.id);
      }
      if (!mounted) return;
      setState(() {
        _students = list;
        _child = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  StudentInfo? get _current => _students.isEmpty ? null : _students[_child];

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    final withResults = member.hasStudentView;

    if (_loading) return const Scaffold(body: LoadingView());
    if (_error != null) {
      return Scaffold(
        body: MessageView(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your account',
          message: _error!,
          onRetry: _load,
        ),
      );
    }

    final isTeacher = member.role == 'teacher';
    final tabs = <({String title, String nav, IconData icon, IconData iconOn, Widget page})>[
      if (withResults)
        (
          title: 'Results',
          nav: 'Results',
          icon: Icons.assignment_outlined,
          iconOn: Icons.assignment,
          page: ResultsScreen(key: ValueKey('r-${_current?.id}'), student: _current),
        ),
      if (isTeacher)
        (
          title: 'My classes',
          nav: 'Classes',
          icon: Icons.class_outlined,
          iconOn: Icons.class_,
          page: TeacherHomeScreen(school: widget.school),
        ),
      (
        title: 'Announcements',
        nav: 'News',
        icon: Icons.campaign_outlined,
        iconOn: Icons.campaign,
        page: AnnouncementsScreen(schoolId: widget.school.id),
      ),
      (
        title: withResults ? 'Profile' : 'Account',
        nav: withResults ? 'Profile' : 'Account',
        icon: Icons.person_outline,
        iconOn: Icons.person,
        page: ProfileScreen(
          key: ValueKey('p-${_current?.id}'),
          school: widget.school,
          member: member,
          student: _current,
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(tabs[_tab].title),
        actions: [
          if (member.isParent && _students.length > 1)
            PopupMenuButton<int>(
              tooltip: 'Switch child',
              icon: const Icon(Icons.family_restroom),
              onSelected: (i) => setState(() => _child = i),
              itemBuilder: (_) => [
                for (var i = 0; i < _students.length; i++)
                  CheckedPopupMenuItem(
                    value: i,
                    checked: i == _child,
                    child: Text(_students[i].fullName),
                  ),
              ],
            ),
        ],
      ),
      body: tabs[_tab].page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.iconOn), label: t.nav),
        ],
      ),
    );
  }
}
