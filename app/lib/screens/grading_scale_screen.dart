import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/portal_repository.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../data/school_settings_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/async_list.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';
import '../widgets/help.dart';

/// Which total score earns which grade. A grade starts at its minimum score and runs up to the next grade.
class GradingScaleScreen extends StatelessWidget {
  const GradingScaleScreen({super.key, required this.school});

  final School school;

  Future<bool?> _edit(BuildContext context, {GradeBand? band}) {
    return showFormSheet(
      context,
      title: band == null ? 'New grade' : 'Edit grade',
      submitLabel: 'Save',
      fields: [
        FieldSpec('grade', 'Grade', required: true, initial: band?.grade, hint: 'A'),
        FieldSpec('min', 'Starts at (score)', required: true, initial: band == null ? '' : fmt(band.minScore),
            keyboard: const TextInputType.numberWithOptions(decimal: true), hint: '70'),
        FieldSpec('remark', 'Meaning (optional)', initial: band?.remark, hint: 'Excellent'),
      ],
      onSubmit: (v) async {
        final grade = v['grade']!.toUpperCase();
        final min = double.tryParse(v['min']!.replaceAll(',', '.'));
        if (grade.isEmpty || grade.length > 3) throw FormError('A grade is 1 to 3 characters, for example A or B+.');
        if (min == null || min < 0 || min > 100) throw FormError('The starting score must be from 0 to 100.');
        final repo = SchoolSettingsRepository.instance;
        final remark = v['remark']!.isEmpty ? null : v['remark'];
        try {
          if (band == null) {
            await repo.addBand(school.id, grade, min, remark);
          } else {
            await repo.updateBand(school.id, band.grade, grade, min, remark);
          }
        } catch (e) {
          final text = e.toString();
          throw FormError(text.contains('23505')
              ? 'That grade, or that starting score, is already used by another grade.'
              : friendlyError(e));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grading scale'),
        actions: const [
          HelpButton(
            title: 'Grading scale',
            steps: [
              'Each grade starts at a score and covers everything up to the next grade.',
              'Example: A starts at 70 and B starts at 60, so 65 is a B.',
              'Always keep one grade that starts at 0, so every score gets a grade.',
              'Changes apply to scores saved from now on. Old results keep their grade.',
            ],
          ),
        ],
      ),
      body: AsyncList<GradeBand>(
        load: () => PortalRepository.instance.gradingScale(school.id),
        emptyIcon: Icons.grade_outlined,
        emptyTitle: 'No grades yet',
        emptyMessage: 'Add a grade that starts at 0 first, then the others.',
        addLabel: 'New grade',
        onAdd: () => _edit(context),
        itemBuilder: (ctx, b, reload) => AppCard(
          onTap: () async {
            if (await _edit(ctx, band: b) == true) await reload();
          },
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(b.grade, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('From ${fmt(b.minScore)} marks', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                if ((b.remark ?? '').isNotEmpty)
                  Text(b.remark!, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline, color: cs.error),
              onPressed: () async {
                if (b.minScore == 0) {
                  notify(ctx, 'Keep one grade that starts at 0. Edit it instead of deleting it.', error: true);
                  return;
                }
                final ok = await confirmDialog(ctx,
                    title: 'Delete grade ${b.grade}?',
                    message: 'Scores in this range will fall into the grade below it from now on.',
                    action: 'Delete',
                    destructive: true);
                if (!ok) return;
                try {
                  await SchoolSettingsRepository.instance.deleteBand(school.id, b.grade);
                  await reload();
                } catch (e) {
                  if (ctx.mounted) notify(ctx, friendlyError(e), error: true);
                }
              },
            ),
          ]),
        ),
      ),
    );
  }
}
