import 'package:flutter/material.dart';

import '../widgets/app_card.dart';

class MoreItem {
  const MoreItem({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

/// The "More" tab: everything that does not need its own bottom-bar slot.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.items});

  final List<MoreItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final it = items[i];
        return AppCard(
          onTap: it.onTap,
          child: Row(children: [
            CircleAvatar(backgroundColor: cs.primary, foregroundColor: cs.onPrimary, child: Icon(it.icon, size: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(it.subtitle, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ]),
        );
      },
    );
  }
}
