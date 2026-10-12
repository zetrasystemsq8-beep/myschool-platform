import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';
import 'help.dart';

/// How a student is doing over time, built only from the published results the user may see.
/// [terms] is newest first (as produced by groupResults).
class ProgressView extends StatelessWidget {
  const ProgressView({super.key, required this.terms});

  final List<TermGroup> terms;

  String _short(TermGroup t) => '${t.sessionName} · T${t.termNumber}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chrono = terms.reversed.toList(); // oldest first
    final latest = terms.first;

    // subject -> term id -> total
    final subjects = <String>{};
    final totals = <String, Map<String, double>>{};
    for (final t in chrono) {
      for (final r in t.rows) {
        subjects.add(r.subjectName);
        if (r.total != null) (totals[r.subjectName] ??= {})[t.termId] = r.total!;
      }
    }
    final names = subjects.toList()..sort();

    final scored = latest.rows.where((r) => r.total != null).toList()
      ..sort((a, b) => b.total!.compareTo(a.total!));

    Widget bar(double value, Color color) => ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (value / 100).clamp(0.0, 1.0),
            minHeight: 10,
            color: color,
            backgroundColor: color.withValues(alpha: 0.14),
          ),
        );

    Widget cell(String subject, int i) {
      final now = totals[subject]?[chrono[i].termId];
      if (now == null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('-', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        );
      }
      final prev = i == 0 ? null : totals[subject]?[chrono[i - 1].termId];
      Widget? arrow;
      if (prev != null && now != prev) {
        arrow = Icon(now > prev ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            size: 20, color: now > prev ? AppTheme.green : cs.error);
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(fmt(now), style: const TextStyle(fontWeight: FontWeight.w600)),
          if (arrow != null) arrow,
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Average by term'),
      AppCard(
        child: Column(children: [
          for (final t in chrono)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(width: 108, child: Text(_short(t), style: theme.textTheme.bodySmall)),
                Expanded(child: bar(t.average ?? 0, AppTheme.green)),
                SizedBox(
                  width: 44,
                  child: Text(fmt(t.average),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
        ]),
      ),
      if (scored.length >= 2) ...[
        const SizedBox(height: 8),
        SectionTitle('Latest term: ${latest.termName}'),
        Row(children: [
          Expanded(
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Strongest', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(scored.first.subjectName,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text(fmt(scored.first.total), style: TextStyle(color: AppTheme.green, fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Needs attention', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(scored.last.subjectName,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text(fmt(scored.last.total), style: const TextStyle(color: Color(0xFFE07B00), fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        ]),
      ],
      const SizedBox(height: 8),
      const SectionTitle('Subjects over time'),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(84),
            columnWidths: const {0: FixedColumnWidth(120)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(children: [
                const SizedBox.shrink(),
                for (final t in chrono)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(_short(t),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
              ]),
              for (final s in names)
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 6, right: 6),
                    child: Text(s, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                  ),
                  for (var i = 0; i < chrono.length; i++) cell(s, i),
                ]),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('Arrows compare each subject with the term before.',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
    ]);
  }
}
