import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/models.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../data/teacher_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/state_views.dart';

class _Invalid implements Exception {
  _Invalid(this.message);
  final String message;
}

/// Teacher enters CA + exam scores for every student of one class/subject/term, saves,
/// then submits the sheet for the administrator's approval.
class ResultEntryScreen extends StatefulWidget {
  const ResultEntryScreen({
    super.key,
    required this.school,
    required this.assignment,
    required this.term,
  });

  final School school;
  final Assignment assignment;
  final TermInfo term;

  @override
  State<ResultEntryScreen> createState() => _ResultEntryScreenState();
}

class _ResultEntryScreenState extends State<ResultEntryScreen> {
  final _repo = TeacherRepository.instance;
  final Map<String, TextEditingController> _ca = {};
  final Map<String, TextEditingController> _exam = {};
  final Map<String, ScoreItem> _saved = {};

  bool _loading = true;
  bool _busy = false;
  String? _error;
  Limits _limits = const Limits(40, 60);
  SheetInfo? _sheet;
  List<RosterEntry> _roster = const [];

  bool get _editable => _sheet == null || _sheet!.isDraft;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ca.values) {
      c.dispose();
    }
    for (final c in _exam.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _text(double? v) => v == null ? '' : fmt(v);

  void _applyItems(List<ScoreItem> items) {
    _saved
      ..clear()
      ..addEntries(items.map((i) => MapEntry(i.studentId, i)));
    for (final r in _roster) {
      final item = _saved[r.studentId];
      _ca.putIfAbsent(r.studentId, () => TextEditingController()).text = _text(item?.ca);
      _exam.putIfAbsent(r.studentId, () => TextEditingController()).text = _text(item?.exam);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final a = widget.assignment;
      final limits = await _repo.limits(widget.school.id);
      final roster = await _repo.roster(a.classId, a.sessionId);
      final sheet = await _repo.findSheet(widget.term.id, a.classId, a.subjectId);
      final items = sheet == null ? <ScoreItem>[] : await _repo.items(sheet.id);
      if (!mounted) return;
      _roster = roster;
      _applyItems(items);
      setState(() {
        _limits = limits;
        _sheet = sheet;
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

  double? _read(TextEditingController c, double max, String what, RosterEntry r) {
    final t = c.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) throw _Invalid('${r.name}: $what must be a number.');
    if (v < 0 || v > max) {
      throw _Invalid('${r.name}: $what must be between 0 and ${fmt(max)}.');
    }
    return v;
  }

  List<Map<String, dynamic>> _collect() {
    final rows = <Map<String, dynamic>>[];
    for (final r in _roster) {
      final ca = _read(_ca[r.studentId]!, _limits.caMax, 'CA', r);
      final exam = _read(_exam[r.studentId]!, _limits.examMax, 'Exam', r);
      if (ca != null || exam != null || _saved.containsKey(r.studentId)) {
        rows.add({'student_id': r.studentId, 'ca_score': ca, 'exam_score': exam});
      }
    }
    return rows;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Saves all typed scores. Returns true when everything was stored.
  Future<bool> _save() async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = _collect();
    } on _Invalid catch (e) {
      _toast(e.message);
      return false;
    }
    setState(() => _busy = true);
    try {
      final a = widget.assignment;
      var sheet = _sheet;
      sheet ??= await _repo.createSheet(
          widget.school.id, AuthRepository.instance.userId!, widget.term.id, a.classId, a.subjectId);
      final payload = [
        for (final r in rows) {...r, 'school_id': widget.school.id, 'sheet_id': sheet.id},
      ];
      if (payload.isNotEmpty) await _repo.saveItems(payload);
      final items = await _repo.items(sheet.id);
      if (!mounted) return false;
      _applyItems(items);
      setState(() {
        _sheet = sheet;
        _busy = false;
      });
      return true;
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _toast(friendlyError(e));
      return false;
    }
  }

  Future<void> _saveTapped() async {
    if (await _save()) _toast('Scores saved.');
  }

  Future<void> _submitTapped() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit for approval?'),
        content: const Text(
            'After submitting you cannot edit these scores unless the administrator returns the sheet to you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!await _save()) return;
    setState(() => _busy = true);
    try {
      final a = widget.assignment;
      await _repo.submit(_sheet!.id);
      final fresh = await _repo.findSheet(widget.term.id, a.classId, a.subjectId);
      if (!mounted) return;
      setState(() {
        _sheet = fresh ?? _sheet;
        _busy = false;
      });
      _toast('Submitted for approval.');
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _toast(friendlyError(e));
    }
  }

  int get _scoredCount => _roster.where((r) => _saved[r.studentId]?.total != null).length;

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    return Scaffold(
      appBar: AppBar(
        title: Text('${a.subjectName} · ${a.className}'),
      ),
      body: _body(),
      bottomNavigationBar: (_loading || _error != null || !_editable || _roster.isEmpty)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _saveTapped,
                      child: const Text('Save'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _submitTapped,
                      child: _busy
                          ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const Text('Submit'),
                    ),
                  ),
                ]),
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
    if (_roster.isEmpty) {
      return const MessageView(
        icon: Icons.groups_outlined,
        title: 'No students in this class',
        message: 'Students must be enrolled in this class for the session before scores can be entered.',
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final note = (_sheet?.returnNote ?? '').trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(children: [
          Expanded(
            child: Text('${widget.term.name} · ${widget.assignment.sessionName}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          _StatusChip(label: _sheet?.label ?? 'Not started', status: _sheet?.status),
        ]),
        const SizedBox(height: 4),
        Text('Scored $_scoredCount of ${_roster.length} students  ·  CA max ${fmt(_limits.caMax)}, Exam max ${fmt(_limits.examMax)}',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        if (note.isNotEmpty && _editable) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
            child: Text('Returned by your administrator: $note',
                style: TextStyle(color: cs.onErrorContainer)),
          ),
        ],
        if (!_editable) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
            child: Text('This sheet is ${_sheet!.label.toLowerCase()}, so scores are locked.'),
          ),
        ],
        const SizedBox(height: 12),
        for (final r in _roster) ...[
          _StudentRow(
            entry: r,
            ca: _ca[r.studentId]!,
            exam: _exam[r.studentId]!,
            caMax: _limits.caMax,
            examMax: _limits.examMax,
            saved: _saved[r.studentId],
            enabled: _editable && !_busy,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.status});

  final String label;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'submitted' => const Color(0xFFE07B00),
      'approved' => const Color(0xFF1565C0),
      'published' => const Color(0xFF1B8A5A),
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

class _StudentRow extends StatefulWidget {
  const _StudentRow({
    required this.entry,
    required this.ca,
    required this.exam,
    required this.caMax,
    required this.examMax,
    required this.saved,
    required this.enabled,
  });

  final RosterEntry entry;
  final TextEditingController ca;
  final TextEditingController exam;
  final double caMax;
  final double examMax;
  final ScoreItem? saved;
  final bool enabled;

  @override
  State<_StudentRow> createState() => _StudentRowState();
}

class _StudentRowState extends State<_StudentRow> {
  double? _val(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ca = _val(widget.ca);
    final exam = _val(widget.exam);
    final live = (ca == null && exam == null) ? null : (ca ?? 0) + (exam ?? 0);
    final grade = widget.saved?.grade;

    Widget field(TextEditingController c, String label, double max) => Expanded(
          child: TextField(
            controller: c,
            enabled: widget.enabled,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: label,
              hintText: '0-${fmt(max)}',
              isDense: true,
            ),
          ),
        );

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.entry.name,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(widget.entry.admissionNumber,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            Text('Total ${fmt(live)}',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            if (grade != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(grade, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          Row(children: [
            field(widget.ca, 'CA', widget.caMax),
            const SizedBox(width: 10),
            field(widget.exam, 'Exam', widget.examMax),
          ]),
        ]),
      ),
    );
  }
}
