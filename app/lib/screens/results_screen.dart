import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/portal_repository.dart';
import '../data/school_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/state_views.dart';

/// Published results for one student. Previous sessions/terms are the chips at the top.
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.student});

  final StudentInfo? student;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  List<TermGroup> _terms = const [];
  int _selected = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final student = widget.student;
    if (student == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await PortalRepository.instance.results(student.id);
      if (!mounted) return;
      setState(() {
        _terms = groupResults(rows);
        _selected = 0;
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

  @override
  Widget build(BuildContext context) {
    if (widget.student == null) {
      return const MessageView(
        icon: Icons.person_search_outlined,
        title: 'No student linked',
        message: 'This account is not linked to a student yet. Please contact your school.',
      );
    }
    if (_loading) return const LoadingView();
    if (_error != null) {
      return MessageView(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load results',
          message: _error!,
          onRetry: _load);
    }
    if (_terms.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 120),
          MessageView(
            icon: Icons.hourglass_empty,
            title: 'No results yet',
            message: 'Results appear here once your school publishes them.',
          ),
        ]),
      );
    }

    final term = _terms[_selected];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(widget.student!.fullName,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text('Admission no. ${widget.student!.admissionNumber}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _terms.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ChoiceChip(
                label: Text(_terms[i].label),
                selected: i == _selected,
                onSelected: (_) => setState(() => _selected = i),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _Summary(term: term),
          const SizedBox(height: 14),
          for (final row in term.rows) ...[
            _SubjectCard(row: row),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.term});

  final TermGroup term;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Expanded(
          child: Column(children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppTheme.green, AppTheme.greenLight]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: [
        Text('${term.className}  ·  ${term.label}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppTheme.gold, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        Row(children: [
          stat('Subjects', '${term.rows.length}'),
          stat('Total', fmt(term.totalScore)),
          stat('Average', fmt(term.average)),
        ]),
      ]),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.row});

  final ResultRow row;

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
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.subjectName,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('CA ${fmt(row.ca)}   ·   Exam ${fmt(row.exam)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                if ((row.remark ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(row.remark!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmt(row.total),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _GradeChip(grade: row.grade),
          ]),
        ]),
      ),
    );
  }
}

class _GradeChip extends StatelessWidget {
  const _GradeChip({required this.grade});

  final String? grade;

  Color get _color {
    switch ((grade ?? '').toUpperCase()) {
      case 'A':
      case 'B':
        return const Color(0xFF1B8A5A);
      case 'C':
        return const Color(0xFFB8860B);
      case 'D':
      case 'E':
        return const Color(0xFFE07B00);
      case 'F':
        return const Color(0xFFC62828);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(grade ?? '-',
          style: TextStyle(color: _color, fontWeight: FontWeight.bold)),
    );
  }
}
