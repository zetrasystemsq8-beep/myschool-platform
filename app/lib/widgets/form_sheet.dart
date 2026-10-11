import 'package:flutter/material.dart';

import '../data/school_repository.dart';

enum FieldKind { text, password, multiline, choice, date, toggle }

/// Describes one input of a form; [FormSheet] builds the widgets and keeps the values.
class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.kind = FieldKind.text,
    this.required = false,
    this.hint,
    this.options = const [],
    this.initial,
    this.keyboard,
  });

  final String key;
  final String label;
  final FieldKind kind;
  final bool required;
  final String? hint;

  /// For [FieldKind.choice]: (id, label) pairs.
  final List<(String, String)> options;
  final String? initial;
  final TextInputType? keyboard;
}

/// Throw this from onSubmit to show a message inside the form.
class FormError implements Exception {
  FormError(this.message);
  final String message;
}

/// Opens a bottom-sheet form. Returns true when [onSubmit] succeeded.
Future<bool?> showFormSheet(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  required String submitLabel,
  required Future<void> Function(Map<String, String> values) onSubmit,
  String? subtitle,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FormSheet(
      title: title,
      subtitle: subtitle,
      fields: fields,
      submitLabel: submitLabel,
      onSubmit: onSubmit,
    ),
  );
}

class _FormSheet extends StatefulWidget {
  const _FormSheet({
    required this.title,
    required this.fields,
    required this.submitLabel,
    required this.onSubmit,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<FieldSpec> fields;
  final String submitLabel;
  final Future<void> Function(Map<String, String>) onSubmit;

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  final Map<String, TextEditingController> _ctl = {};
  final Map<String, String> _vals = {};
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      switch (f.kind) {
        case FieldKind.text:
        case FieldKind.password:
        case FieldKind.multiline:
          _ctl[f.key] = TextEditingController(text: f.initial ?? '');
        case FieldKind.choice:
        case FieldKind.date:
          _vals[f.key] = f.initial ?? '';
        case FieldKind.toggle:
          _vals[f.key] = f.initial ?? 'false';
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _pickDate(FieldSpec f) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_vals[f.key] ?? '') ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _vals[f.key] = '${picked.year}-${_two(picked.month)}-${_two(picked.day)}');
    }
  }

  Future<void> _pickChoice(FieldSpec f) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(f.label, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            if (f.options.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nothing to choose from yet. Create some first.'),
              ),
            if (!f.required)
              ListTile(title: const Text('None'), onTap: () => Navigator.pop(ctx, '')),
            for (final o in f.options)
              ListTile(
                title: Text(o.$2),
                trailing: _vals[f.key] == o.$1 ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, o.$1),
              ),
          ]),
        ),
      ),
    );
    if (picked != null) setState(() => _vals[f.key] = picked);
  }

  Future<void> _submit() async {
    final values = <String, String>{};
    for (final f in widget.fields) {
      final v = _ctl[f.key]?.text.trim() ?? _vals[f.key] ?? '';
      if (f.required && f.kind != FieldKind.toggle && v.isEmpty) {
        setState(() => _error = 'Please fill in: ${f.label}');
        return;
      }
      values[f.key] = v;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(values);
      if (mounted) Navigator.pop(context, true);
    } on FormError catch (e) {
      if (mounted) setState(() { _error = e.message; _busy = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _busy = false; });
    }
  }

  Widget _field(FieldSpec f) {
    final theme = Theme.of(context);
    switch (f.kind) {
      case FieldKind.text:
      case FieldKind.password:
      case FieldKind.multiline:
        final pw = f.kind == FieldKind.password;
        return TextField(
          controller: _ctl[f.key],
          obscureText: pw && _hidden,
          autocorrect: false,
          enabled: !_busy,
          minLines: f.kind == FieldKind.multiline ? 3 : 1,
          maxLines: f.kind == FieldKind.multiline ? 6 : 1,
          keyboardType: f.keyboard,
          decoration: InputDecoration(
            labelText: f.required ? '${f.label} *' : f.label,
            hintText: f.hint,
            suffixIcon: pw
                ? IconButton(
                    icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : null,
          ),
        );
      case FieldKind.choice:
        final id = _vals[f.key] ?? '';
        final label = f.options.where((o) => o.$1 == id).map((o) => o.$2).firstOrNull;
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy ? null : () => _pickChoice(f),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: f.required ? '${f.label} *' : f.label,
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            child: Text(label ?? (f.hint ?? 'Tap to choose'),
                style: label == null
                    ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
                    : null),
          ),
        );
      case FieldKind.date:
        final v = _vals[f.key] ?? '';
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy ? null : () => _pickDate(f),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: f.required ? '${f.label} *' : f.label,
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
            ),
            child: Text(v.isEmpty ? 'Tap to pick a date' : v,
                style: v.isEmpty ? TextStyle(color: theme.colorScheme.onSurfaceVariant) : null),
          ),
        );
      case FieldKind.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _vals[f.key] == 'true',
          onChanged: _busy ? null : (v) => setState(() => _vals[f.key] = v ? 'true' : 'false'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(widget.subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 16),
          for (final f in widget.fields) ...[_field(f), const SizedBox(height: 12)],
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(widget.submitLabel),
          ),
        ]),
      ),
    );
  }
}
