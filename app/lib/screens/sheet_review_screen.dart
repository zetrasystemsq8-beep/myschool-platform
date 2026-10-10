import 'package:flutter/material.dart';

import '../data/admin_repository.dart';
import '../data/models.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/state_views.dart';

/// Look at every score of one sheet, then approve / publish / return / unpublish it.
class SheetReviewScreen extends StatefulWidget {
  const SheetReviewScreen({super.key, required this.school, required this.sheet});

  final School school;
  final SheetSummary sheet;

  @override
  State<SheetReviewScreen> createState() => _SheetReviewScreenState();
}

class _SheetReviewScreenState extends State<SheetReviewScreen> {
  final _repo = AdminRepository.instance;
  late SheetSummary _sheet;
  List<ReviewItem> _items = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sheet = widget.sheet;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fresh = await _repo.sheet(_sheet.id);
      final items = await _repo.items(_sheet.id);
      if (!mounted) return;
      setState(() {
        _sheet = fresh ?? _sheet;
        _items = items;
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

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<String?> _askReason(String title, String hint) {
    final ctl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final t = ctl.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      _toast(done);
      await _load();
    } catch (e) {
      _toast(friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _approve() async {
    if (await _confirm('Approve this sheet?', 'You can publish it afterwards.', 'Approve')) {
      await _run(() => _repo.approve(_sheet.id), 'Approved.');
    }
  }

  Future<void> _publish() async {
    if (await _confirm('Publish results?',
        'Students and parents will see these results immediately.', 'Publish')) {
      await _run(() => _repo.publish(_sheet.id), 'Published.');
    }
  }

  Future<void> _return() async {
    final note = await _askReason('Return to teacher', 'What should be corrected?');
    if (note != null) await _run(() => _repo.returnToTeacher(_sheet.id, note), 'Returned to teacher.');
  }

  Future<void> _unpublish() async {
    final reason = await _askReason('Unpublish results', 'Why are you unpublishing?');
    if (reason != null) await _run(() => _repo.unpublish(_sheet.id, reason), 'Unpublished.');
  }

  List<Widget> _actions() {
    Widget outlined(String label, VoidCallback f) =>
        Expanded(child: OutlinedButton(onPressed: _busy ? null : f, child: Text(label)));
    Widget filled(String label, VoidCallback f) => Expanded(
          child: FilledButton(
            onPressed: _busy ? null : f,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(label),
          ),
        );
    const gap = SizedBox(width: 12);
    switch (_sheet.status) {
      case 'submitted':
        return [outlined('Return', _return), gap, filled('Approve', _approve)];
      case 'approved':
        return [outlined('Return', _return), gap, filled('Publish', _publish)];
      case 'published':
        return [outlined('Unpublish', _unpublish)];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions();
    return Scaffold(
      appBar: AppBar(title: Text('${_sheet.subjectName} · ${_sheet.className}')),
      body: _body(),
      bottomNavigationBar: (_loading || _error != null || actions.isEmpty)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: actions),
              ),
            ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return MessageView(
          icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load);
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final totals = _items.map((i) => i.total).whereType<double>().toList();
    final avg = totals.isEmpty ? null : totals.reduce((a, b) => a + b) / totals.length;
    final hi = totals.isEmpty ? null : totals.reduce((a, b) => a > b ? a : b);
    final lo = totals.isEmpty ? null : totals.reduce((a, b) => a < b ? a : b);
    final note = (_sheet.returnNote ?? '').trim();

    Widget stat(String label, String value) => Expanded(
          child: Column(children: [
            Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(children: [
          Expanded(
            child: Text('${_sheet.termName} · ${_sheet.sessionName}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Chip(label: Text(_sheet.statusLabel), visualDensity: VisualDensity.compact),
        ]),
        if (note.isNotEmpty && _sheet.status != 'published') ...[
          const SizedBox(height: 8),
          Text('Last note: $note',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppTheme.green, AppTheme.greenLight]),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(children: [
            stat('Students', '${_items.length}'),
            stat('Average', fmt(avg)),
            stat('Highest', fmt(hi)),
            stat('Lowest', fmt(lo)),
          ]),
        ),
        const SizedBox(height: 14),
        if (_items.isEmpty)
          const MessageView(
            icon: Icons.hourglass_empty,
            title: 'No scores yet',
            message: 'The teacher has not entered scores for this sheet.',
          ),
        for (final i in _items) ...[
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text('${i.admissionNumber}  ·  CA ${fmt(i.ca)}  ·  Exam ${fmt(i.exam)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
                Text(fmt(i.total), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(8)),
                  child: Text(i.grade ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
