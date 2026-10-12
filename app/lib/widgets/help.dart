import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// "?" button that explains the current screen in plain steps.
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.title, required this.steps, this.intro});

  final String title;
  final String? intro;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Help',
      icon: const Icon(Icons.help_outline),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                children: [
                  Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  if (intro != null) ...[
                    const SizedBox(height: 8),
                    Text(intro!,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 18),
                  for (var i = 0; i < steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: AppTheme.green,
                          child: Text('${i + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(steps[i], style: theme.textTheme.bodyLarge)),
                      ]),
                    ),
                  const SizedBox(height: 6),
                  FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A short, friendly note at the top of a screen.
class HintBanner extends StatelessWidget {
  const HintBanner({super.key, required this.text, this.icon = Icons.lightbulb_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: AppTheme.gold),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6),
      child: Row(children: [
        Expanded(
          child: Text(text, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ]),
    );
  }
}
