import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/notification_repository.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/help.dart';
import '../widgets/state_views.dart';

/// Notification centre. Pops with a tab id (e.g. "notices") when a notification should open a tab.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.school});

  final School school;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItem> _items = const [];
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
      final list = await NotificationRepository.instance.list(widget.school.id);
      if (!mounted) return;
      setState(() {
        _items = list;
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

  Future<void> _open(NotificationItem n) async {
    if (!n.isRead) {
      try {
        await NotificationRepository.instance.markRead(n.id);
      } catch (_) {
        // Not critical: it will simply stay unread.
      }
    }
    if (!mounted) return;
    final target = switch (n.kind) {
      'announcement' => 'notices',
      'meeting' => 'meetings',
      'message' => 'messages',
      'message_report' => 'moderation',
      _ => null,
    };
    if (target != null) Navigator.pop(context, target);
  }

  Future<void> _markAll() async {
    try {
      await NotificationRepository.instance.markAllRead(widget.school.id);
      await _load();
    } catch (e) {
      if (mounted) notify(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasUnread = _items.any((n) => !n.isRead);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread) TextButton(onPressed: _markAll, child: const Text('Mark all read')),
          const HelpButton(
            title: 'Notifications',
            steps: [
              'You get a notification when your school publishes a notice meant for you.',
              'A gold dot means you have not opened it yet.',
              'Tap a notification to open it. Tap "Mark all read" to clear the dots.',
            ],
          ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? MessageView(
                  icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const MessageView(
                      icon: Icons.notifications_none,
                      title: 'Nothing new',
                      message: 'When your school publishes a notice for you, it will show up here.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final n = _items[i];
                          return AppCard(
                            onTap: () => _open(n),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6, right: 12),
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: n.isRead ? Colors.transparent : AppTheme.gold,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(n.title,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: n.isRead ? FontWeight.w500 : FontWeight.bold)),
                                  if ((n.body ?? '').isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(n.body!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(formatDate(n.createdAt),
                                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                                ]),
                              ),
                            ]),
                          );
                        },
                      ),
                    ),
    );
  }
}
