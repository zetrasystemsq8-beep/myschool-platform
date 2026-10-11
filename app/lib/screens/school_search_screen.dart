import 'dart:async';

import 'package:flutter/material.dart';

import '../data/school.dart';
import '../data/school_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/school_card.dart';
import '../widgets/state_views.dart';
import 'platform_admin_screen.dart';
import 'school_home_screen.dart';

class SchoolSearchScreen extends StatefulWidget {
  const SchoolSearchScreen({super.key});

  @override
  State<SchoolSearchScreen> createState() => _SchoolSearchScreenState();
}

class _SchoolSearchScreenState extends State<SchoolSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;
  List<School> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final id = ++_requestId;
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query, id));
  }

  Future<void> _search(String query, int id) async {
    try {
      final found = await SchoolRepository.instance.search(query);
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = found;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _open(School school) async {
    await SchoolRepository.instance.saveSchool(school);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SchoolHomeScreen(school: school)),
    );
  }

  /// Hidden on purpose: long-press the MySchool logo.
  void _teamSignIn() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlatformAdminScreen()),
    );
  }

  Widget _header() {
    final cs = Theme.of(context).colorScheme;
    final top = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, top + 20, 20, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.green, AppTheme.greenLight],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onLongPress: _teamSignIn,
          behavior: HitTestBehavior.opaque,
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.gold, width: 1.5),
              ),
              child: const Icon(Icons.school_rounded, color: AppTheme.gold, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('MySchool',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
        ),
        const SizedBox(height: 28),
        const Text('Find your school',
            style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Search by school name or School ID',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15)),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            filled: true,
            fillColor: cs.surface,
            hintText: 'School name or School ID',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _howItWorks() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget step(IconData icon, String title, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      children: [
        Text('How it works',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        step(Icons.search, 'Find your school',
            'Type at least 2 letters of the school name, or its School ID.'),
        step(Icons.login, 'Sign in',
            'Students use their admission number and PIN. Parents and staff use their email.'),
        step(Icons.assignment_outlined, 'Stay up to date',
            'See published results and announcements from your school.'),
      ],
    );
  }

  Widget _body() {
    if (_error != null) {
      return MessageView(
        icon: Icons.cloud_off_outlined,
        title: 'Could not search',
        message: _error!,
        onRetry: () => _onChanged(_controller.text),
      );
    }
    if (_controller.text.trim().length < 2) return _howItWorks();
    if (_loading) return const LoadingView();
    if (_results.isEmpty) {
      return const MessageView(
        icon: Icons.school_outlined,
        title: 'No school found',
        message: 'Check the spelling, or ask your school for its School ID.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) =>
          SchoolCard(school: _results[i], onTap: () => _open(_results[i])),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        _header(),
        Expanded(child: SafeArea(top: false, child: _body())),
      ]),
    );
  }
}
