import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/portal_repository.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/help.dart';
import '../widgets/state_views.dart';

/// Class-level progress for teachers (their own subjects) and administrators (all).
/// Built from approved and shared results only; the database decides what each person may see.
class ClassSummaryScreen extends StatefulWidget {
  const ClassSummaryScreen({super.key, required this.school});

  final School school;

  @override
  State<ClassSummaryScreen> createState() => _ClassSummaryScreenState();
}

class _ClassSummaryScreenState extends State<ClassSummaryScreen> {
  List<ClassSummaryRow> _rows = const [];
  List<ClassSummaryRow> _termHeads = const []; // one row per term, newest first
  int _selected = 0;
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
      final rows = await PortalRepository.instance.classSummary(widget.school.id);
      final byTerm = <String, ClassSummaryRow>{};
      for (final r in rows) {
        byTerm.putIfAbsent(r.termId, () => r);
      }
      final heads = byTerm.values.toList()
        ..sort((a, b) {
          final s = b.sessionName.compareTo(a.sessionName);
          return s != 0 ? s : b.termNumber.compareTo(a.termNumber);
        });
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _termHeads = heads;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Class results summary'),
        actions: const [
          HelpButton(
            title: 'Class results summary',
            steps: [
              'Pick a term at the top.',
              'Each card is one class, with the average for each subject, and the lowest and highest score.',
              'Only results that are approved or shared are counted. Teachers see their own subjects.',
            ],
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return MessageView(
          icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load);
    }
    if (_termHeads.isEmpty) {
      return const MessageView(
        icon: Icons.bar_chart,
        title: 'Nothing to summarise yet',
        message: 'Summaries appear once results are approved by the administrator.',
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final termId = _termHeads[_selected].termId;
    final inTerm = _rows.where((r) => r.termId == termId).toList();
    final classes = <String, List<ClassSummaryRow>>{};
    for (final r in inTerm) {
      (classes[r.className] ??= []).add(r);
    }
    final classNames = classes.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _termHeads.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ChoiceChip(
                label: Text(_termHeads[i].termLabel),
                selected: i == _selected,
                onSelected: (_) => setState(() => _selected = i),
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final name in classNames) ...[
            _ClassCard(className: name, rows: classes[name]!..sort((a, b) => a.subjectName.compareTo(b.subjectName))),
            const SizedBox(height: 12),
          ],
          Text('Based on approved and shared results only.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.className, required this.rows});

  final String className;
  final List<ClassSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final avgs = rows.map((r) => r.average).whereType<double>().toList();
    final overall = avgs.isEmpty ? null : avgs.reduce((a, b) => a + b) / avgs.length;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(className, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Text('Class average ${fmt(overall)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.green, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 10),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(r.subjectName, style: theme.textTheme.bodyMedium)),
                if (r.status != 'published') const StatusPill(label: 'Not shared yet', color: Color(0xFFE07B00)),
                const SizedBox(width: 8),
                Text(fmt(r.average), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ((r.average ?? 0) / 100).clamp(0.0, 1.0),
                  minHeight: 8,
                  color: AppTheme.green,
                  backgroundColor: AppTheme.green.withValues(alpha: 0.14),
                ),
              ),
              const SizedBox(height: 2),
              Text('${r.scored} students  ·  lowest ${fmt(r.lowest)}  ·  highest ${fmt(r.highest)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
      ]),
    );
  }
}
