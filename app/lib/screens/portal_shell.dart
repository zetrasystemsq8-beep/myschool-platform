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

    final pages = <Widget>[
      if (withResults)
        ResultsScreen(key: ValueKey('r-${_current?.id}'), student: _current),
      AnnouncementsScreen(schoolId: widget.school.id),
      ProfileScreen(
        key: ValueKey('p-${_current?.id}'),
        school: widget.school,
        member: member,
        student: _current,
      ),
    ];
    final titles = [
      if (withResults) 'Results',
      'Announcements',
      withResults ? 'Profile' : 'Account',
    ];
    final destinations = <NavigationDestination>[
      if (withResults)
        const NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Results'),
      const NavigationDestination(
          icon: Icon(Icons.campaign_outlined),
          selectedIcon: Icon(Icons.campaign),
          label: 'News'),
      NavigationDestination(
          icon: const Icon(Icons.person_outline),
          selectedIcon: const Icon(Icons.person),
          label: withResults ? 'Profile' : 'Account'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
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
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: destinations,
      ),
    );
  }
}
