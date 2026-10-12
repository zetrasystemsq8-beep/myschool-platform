import 'package:flutter/material.dart';

import '../data/admin_repository.dart';
import '../data/models.dart';
import '../data/school_repository.dart';
import '../data/setup_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/async_list.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';

/// Administrator's notice manager: write, publish (this also notifies the people it is for),
/// archive, delete. A notice can be for the whole school or for one class.
class AdminAnnouncementsScreen extends StatelessWidget {
  const AdminAnnouncementsScreen({super.key, required this.schoolId});

  final String schoolId;

  Future<bool?> _edit(BuildContext context, [Announcement? a]) async {
    try {
      final classes = await SetupRepository.instance.classes(schoolId);
      if (!context.mounted) return false;
      return showFormSheet(
        context,
        title: a == null ? 'New notice' : 'Edit notice',
        subtitle: 'Publishing a notice sends a notification to the people it is for.',
        submitLabel: 'Save',
        fields: [
          FieldSpec('title', 'Title', required: true, initial: a?.title),
          FieldSpec('body', 'Message', kind: FieldKind.multiline, required: true, initial: a?.body),
          FieldSpec('audience', 'Who is it for?',
              kind: FieldKind.choice,
              required: true,
              initial: a?.audience ?? 'all',
              options: const [
                ('all', 'Everyone'),
                ('students', 'Students'),
                ('parents', 'Parents'),
                ('staff', 'Staff'),
              ]),
          FieldSpec('class', 'Only for one class? (optional)',
              kind: FieldKind.choice,
              hint: 'Whole school',
              initial: a?.classId ?? '',
              options: [for (final c in classes) (c.id, c.name)]),
          FieldSpec('status', 'Status',
              kind: FieldKind.choice,
              required: true,
              initial: a?.status ?? 'published',
              options: const [
                ('draft', 'Draft (only you can see it)'),
                ('published', 'Published'),
                ('archived', 'Archived'),
              ]),
        ],
        onSubmit: (v) async {
          try {
            await AdminRepository.instance.saveAnnouncement(
              id: a?.id,
              schoolId: schoolId,
              title: v['title']!,
              body: v['body']!,
              audience: v['audience']!,
              status: v['status']!,
              classId: v['class']!.isEmpty ? null : v['class'],
            );
          } catch (e) {
            throw FormError(friendlyError(e));
          }
        },
      );
    } catch (e) {
      if (context.mounted) notify(context, friendlyError(e), error: true);
      return false;
    }
  }

  Color _statusColor(String s) => switch (s) {
        'published' => AppTheme.green,
        'archived' => Colors.grey,
        _ => const Color(0xFFE07B00),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AsyncList<Announcement>(
      load: () => AdminRepository.instance.announcements(schoolId),
      emptyIcon: Icons.campaign_outlined,
      emptyTitle: 'No notices yet',
      emptyMessage: 'Tap New to write the first one.',
      addLabel: 'New',
      onAdd: () => _edit(context),
      itemBuilder: (ctx, a, reload) => AppCard(
        onTap: () async {
          if (await _edit(ctx, a) == true) await reload();
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(a.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            StatusPill(label: a.status, color: _statusColor(a.status)),
            PopupMenuButton<String>(
              onSelected: (_) async {
                final ok = await confirmDialog(ctx,
                    title: 'Delete this notice?',
                    message: 'This cannot be undone. To keep it, archive it instead.',
                    action: 'Delete',
                    destructive: true);
                if (!ok) return;
                try {
                  await AdminRepository.instance.deleteAnnouncement(a.id);
                  await reload();
                } catch (e) {
                  if (ctx.mounted) notify(ctx, friendlyError(e), error: true);
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete'))],
            ),
          ]),
          Text(
            'For: ${a.audience}${(a.className ?? '').isEmpty ? ' (whole school)' : ' · ${a.className}'}'
            '${a.publishedAt == null ? '' : '  ·  ${formatDate(a.publishedAt)}'}',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(a.body, maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}
