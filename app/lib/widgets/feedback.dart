import 'package:flutter/material.dart';

/// One consistent way to tell the user something worked or failed.
void notify(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  final cs = Theme.of(context).colorScheme;
  final fg = error ? cs.onError : cs.onInverseSurface;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: error ? cs.error : null,
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: fg, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: fg))),
      ]),
    ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async {
  final cs = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(100, 44),
            backgroundColor: destructive ? cs.error : null,
            foregroundColor: destructive ? cs.onError : null,
          ),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}
