import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/models.dart';
import '../data/portal_repository.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../widgets/help.dart';
import '../widgets/state_views.dart';
import 'admin_announcements_screen.dart';
import 'admin_review_screen.dart';
import 'admin_fees_screen.dart';
import 'announcements_screen.dart';
import 'attendance_screen.dart';
import 'attendance_view_screen.dart';
import 'fees_screen.dart';
import '../data/notification_repository.dart';
import 'home_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'results_screen.dart';
import 'setup_hub_screen.dart';
import 'teacher_home_screen.dart';

typedef _Tab = ({
  String id,
  String title,
  String nav,
  IconData icon,
  IconData iconOn,
  Widget page,
  HelpButton? help,
});

/// Signed-in area. Every role starts on Home.
///   Student:       Home, Results, Attendance, Notices
///   Parent:        Home, Results, Attendance, Fees, Notices
///   Teacher:       Home, Classes, Attendance, Notices
///   School admin:  Home, Approvals, Fees, My school, Notices
/// Everyone: bell (notifications), profile icon, and a "?" help button in the top bar.
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
  int _unread = 0;

  Future<void> _refreshUnread() async {
    try {
      final n = await NotificationRepository.instance.unreadCount(widget.school.id);
      if (mounted) setState(() => _unread = n);
    } catch (_) {
      // The bell simply shows no badge if this fails.
    }
  }

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
      _refreshUnread();
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
    final isTeacher = member.role == 'teacher';
    final isAdmin = member.role == 'school_admin';

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

    late final List<_Tab> tabs;
    void goTo(String id) {
      final i = tabs.indexWhere((t) => t.id == id);
      if (i >= 0) setState(() => _tab = i);
    }

    final homeHelp = withResults
        ? const HelpButton(
            title: 'Your home page',
            steps: [
              'Home shows your latest results and the newest notices from your school.',
              'Open Results to see every subject and your earlier terms.',
              'Open Notices for news from your school.',
            ],
          )
        : (isTeacher
            ? const HelpButton(
                title: 'Your home page',
                steps: [
                  'Home shows how many classes you teach and which results are waiting.',
                  'Open Classes to enter scores.',
                  'If the administrator sends results back, you will see a reminder here.',
                ],
              )
            : const HelpButton(
                title: 'Your home page',
                steps: [
                  'Home shows how many results are waiting for your approval.',
                  'Follow the "Get your school ready" list until every step is ticked.',
                  'Open Approvals to check, approve and share results.',
                ],
              ));

    tabs = <_Tab>[
      (
        id: 'home',
        title: widget.school.name,
        nav: 'Home',
        icon: Icons.home_outlined,
        iconOn: Icons.home,
        page: HomeScreen(
          key: ValueKey('h-${_current?.id}'),
          school: widget.school,
          member: member,
          student: _current,
          active: _tab == 0,
          onGoTo: goTo,
        ),
        help: homeHelp,
      ),
      if (withResults)
        (
          id: 'results',
          title: 'My results',
          nav: 'Results',
          icon: Icons.assignment_outlined,
          iconOn: Icons.assignment,
          page: ResultsScreen(key: ValueKey('r-${_current?.id}'), student: _current, school: widget.school),
          help: const HelpButton(
            title: 'Your results',
            steps: [
              'Each card is one subject, with the test (CA), exam, total and grade.',
              'Use the buttons at the top to look at earlier terms and years.',
              'Pull down to refresh. New results appear when your school shares them.',
            ],
          ),
        ),
      if (withResults)
        (
          id: 'attendance',
          title: 'Attendance',
          nav: 'Attendance',
          icon: Icons.event_available_outlined,
          iconOn: Icons.event_available,
          page: AttendanceViewScreen(key: ValueKey('a-${_current?.id}'), student: _current),
          help: const HelpButton(
            title: 'Attendance',
            steps: [
              'This shows the days your child was present, late or absent.',
              'Use the arrows at the top to look at other months.',
              '"Attended" counts present and late days together.',
            ],
          ),
        ),
      if (member.isParent)
        (
          id: 'fees',
          title: 'School fees',
          nav: 'Fees',
          icon: Icons.receipt_long_outlined,
          iconOn: Icons.receipt_long,
          page: FeesScreen(key: ValueKey('f-${_current?.id}'), student: _current),
          help: const HelpButton(
            title: 'School fees',
            steps: [
              'Each card is a fee set by the school, with what was paid and what is still owed.',
              'Tap a card to see every payment.',
              'The school office records payments when money is received. Keep your receipt.',
            ],
          ),
        ),
      if (isTeacher)
        (
          id: 'classes',
          title: 'My classes',
          nav: 'Classes',
          icon: Icons.class_outlined,
          iconOn: Icons.class_,
          page: TeacherHomeScreen(school: widget.school),
          help: const HelpButton(
            title: 'My classes',
            steps: [
              'These are the classes and subjects your administrator gave you.',
              'Tap one and choose the term. Then type each student\'s scores.',
              'Tap "Send for approval" when everyone has a score.',
            ],
          ),
        ),
      if (isTeacher)
        (
          id: 'attendance',
          title: 'Attendance',
          nav: 'Attendance',
          icon: Icons.event_available_outlined,
          iconOn: Icons.event_available,
          page: AttendanceScreen(school: widget.school, isAdmin: false),
          help: const HelpButton(
            title: 'Attendance',
            steps: [
              'Pick a class at the top. "Mark attendance" lists the students for the day.',
              'Everyone starts as Present. Change anyone who is Late or Absent, then tap Save.',
              'You can mark today and the last 7 days. Open "Records" to see a month.',
            ],
          ),
        ),
      if (isAdmin)
        (
          id: 'review',
          title: 'Approvals',
          nav: 'Approvals',
          icon: Icons.fact_check_outlined,
          iconOn: Icons.fact_check,
          page: AdminReviewScreen(school: widget.school),
          help: const HelpButton(
            title: 'Approvals',
            intro: 'Teachers send their results here. Students and parents see nothing until you share them.',
            steps: [
              '"Waiting" lists results sent by teachers. Tap one to check the scores.',
              'Tap "Approve" if they are right. Tap "Send back" and write a note if not.',
              'After approving, tap "Share results" so students and parents can see them.',
            ],
          ),
        ),
      if (isAdmin)
        (
          id: 'fees',
          title: 'School fees',
          nav: 'Fees',
          icon: Icons.payments_outlined,
          iconOn: Icons.payments,
          page: AdminFeesScreen(school: widget.school),
          help: adminFeesHelp,
        ),
      if (isAdmin)
        (
          id: 'setup',
          title: 'My school',
          nav: 'My school',
          icon: Icons.settings_outlined,
          iconOn: Icons.settings,
          page: SetupHubScreen(school: widget.school),
          help: const HelpButton(
            title: 'My school',
            steps: [
              'Add the school year and its terms.',
              'Add your classes and subjects.',
              'Add students, teachers and parents, then choose what each teacher teaches.',
            ],
          ),
        ),
      (
        id: 'notices',
        title: 'Notices',
        nav: 'Notices',
        icon: Icons.campaign_outlined,
        iconOn: Icons.campaign,
        page: isAdmin
            ? AdminAnnouncementsScreen(schoolId: widget.school.id)
            : AnnouncementsScreen(schoolId: widget.school.id),
        help: HelpButton(
          title: 'Notices',
          steps: isAdmin
              ? const [
                  'Tap "New" to write a notice for your school.',
                  'Choose who should see it: everyone, students, parents or staff.',
                  '"Draft" is only visible to you. "Published" is visible to the people you chose.',
                ]
              : const [
                  'Notices from your school appear here, newest first.',
                  'Tap one to read all of it. Pull down to refresh.',
                ],
        ),
      ),
    ];

    final current = tabs[_tab];
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(current.title),
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
            IconButton(
              tooltip: 'Notifications',
              icon: Badge(
                label: Text('$_unread'),
                isLabelVisible: _unread > 0,
                child: const Icon(Icons.notifications_outlined),
              ),
              onPressed: () async {
                final target = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => NotificationsScreen(school: widget.school)),
                );
                _refreshUnread();
                if (target != null) goTo(target);
              },
            ),
            IconButton(
              tooltip: 'Profile',
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(
                    title: const Text('Profile'),
                    actions: const [
                      HelpButton(
                        title: 'Your profile',
                        steps: [
                          'See your details and your school.',
                          'Choose Light, Dark or Auto appearance.',
                          'Change your password or PIN here. Tap "Sign out" when you are done.',
                        ],
                      ),
                    ],
                  ),
                  body: ProfileScreen(
                    school: widget.school,
                    member: member,
                    student: _current,
                  ),
                ),
              )),
            ),
            if (current.help != null) current.help!,
          ],
        ),
        body: IndexedStack(index: _tab, children: [for (final t in tabs) t.page]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            setState(() => _tab = i);
            _refreshUnread();
          },
          destinations: [
            for (final t in tabs)
              NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.iconOn), label: t.nav),
          ],
        ),
      ),
    );
  }
}
