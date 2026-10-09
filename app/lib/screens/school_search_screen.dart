import 'dart:async';

import 'package:flutter/material.dart';

import '../data/school.dart';
import '../data/school_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/school_card.dart';
import '../widgets/state_views.dart';
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

  Widget _body() {
    if (_error != null) {
      return MessageView(
        icon: Icons.cloud_off_outlined,
        title: 'Could not search',
        message: _error!,
        onRetry: () => _onChanged(_controller.text),
      );
    }
    if (_controller.text.trim().length < 2) {
      return const MessageView(
        icon: Icons.search,
        title: 'Find your school',
        message: 'Type at least 2 letters of the school name, or its School ID.',
      );
    }
    if (_loading) return const LoadingView();
    if (_results.isEmpty) {
      return const MessageView(
        icon: Icons.school_outlined,
        title: 'No school found',
        message: 'Check the spelling, or ask your school for its School ID.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) =>
          SchoolCard(school: _results[i], onTap: () => _open(_results[i])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.school_rounded,
                          color: AppTheme.gold, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Text('MySchool',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 24),
                  Text('Find your school',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('Search by school name or School ID.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _controller,
                    onChanged: _onChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'e.g. Christ\'s School or CHR-ADO',
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
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }
}
