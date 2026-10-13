import 'package:flutter/material.dart';

import '../data/attendance_repository.dart';
import '../data/auth_repository.dart';
import '../data/models.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../data/setup_repository.dart';
import '../data/teacher_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/help.dart';
import '../widgets/state_views.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

Color statusColor(String status) => switch (status) {
      'present' => AppTheme.green,
      'late' => const Color(0xFFE07B00),
      'absent' => const Color(0xFFC62828),
      _ => Colors.grey,
    };

/// Staff attendance: mark the register, and look at records by month.
/// Teachers see the classes they teach; administrators see every class.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.school, required this.isAdmin});

  final School school;
  final bool isAdmin;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<(String, String)> _classes = const [];
  int _selected = 0;
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
      List<(String, String)> list;
      if (widget.isAdmin) {
        list = [for (final c in await SetupRepository.instance.classes(widget.school.id)) (c.id, c.name)];
      } else {
        final uid = AuthRepository.instance.userId!;
        final seen = <String>{};
        list = [
          for (final a in await TeacherRepository.instance.assignments(uid, widget.school.id))
            if (seen.add(a.classId)) (a.classId, a.className),
        ];
        list.sort((a, b) => a.$2.compareTo(b.$2));
      }
      if (!mounted) return;
      setState(() {
        _classes = list;
        _selected = 0;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return MessageView(icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load);
    }
    if (_classes.isEmpty) {
      return MessageView(
        icon: Icons.class_outlined,
        title: 'No classes yet',
        message: widget.isAdmin
            ? 'Add your classes under My school first.'
            : 'Your administrator has not chosen your classes yet.',
      );
    }
    final classId = _classes[_selected].$1;
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            itemCount: _classes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ChoiceChip(
              label: Text(_classes[i].$2),
              selected: i == _selected,
              onSelected: (_) => setState(() => _selected = i),
            ),
          ),
        ),
        const TabBar(tabs: [Tab(text: 'Mark attendance'), Tab(text: 'Records')]),
        Expanded(
          child: TabBarView(children: [
            _MarkTab(key: ValueKey('m-$classId'), school: widget.school, classId: classId, isAdmin: widget.isAdmin),
            _RecordsTab(key: ValueKey('r-$classId'), school: widget.school, classId: classId),
          ]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ mark

class _MarkTab extends StatefulWidget {
  const _MarkTab({super.key, required this.school, required this.classId, required this.isAdmin});

  final School school;
  final String classId;
  final bool isAdmin;

  @override
  State<_MarkTab> createState() => _MarkTabState();
}

class _MarkTabState extends State<_MarkTab> {
  late DateTime _day = _dateOnly(DateTime.now());
  List<RosterEntry> _roster = const [];
  final Map<String, String> _status = {};
  bool _hasRecords = false;
  bool _noYear = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  DateTime get _today => _dateOnly(DateTime.now());

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
      final sid = await SetupRepository.instance.currentSessionId(widget.school.id);
      if (sid == null) {
        if (!mounted) return;
        setState(() {
          _noYear = true;
          _loading = false;
        });
        return;
      }
      final roster = await TeacherRepository.instance.roster(widget.classId, sid);
      final records = await AttendanceRepository.instance.forClassDay(widget.classId, _day);
      if (!mounted) return;
      _status
        ..clear()
        ..addEntries(roster.map((r) => MapEntry(r.studentId, 'present')));
      for (final rec in records) {
        _status[rec.studentId] = rec.status;
      }
      setState(() {
        _noYear = false;
        _roster = roster;
        _hasRecords = records.isNotEmpty;
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

  void _shift(int days) {
    final d = _day.add(Duration(days: days));
    if (d.isAfter(_today)) return;
    if (!widget.isAdmin && d.isBefore(_today.subtract(const Duration(days: 7)))) return;
    setState(() => _day = d);
    _load();
  }

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: widget.isAdmin ? _today.subtract(const Duration(days: 400)) : _today.subtract(const Duration(days: 7)),
      lastDate: _today,
    );
    if (picked != null) {
      setState(() => _day = _dateOnly(picked));
      _load();
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await AttendanceRepository.instance.mark(widget.classId, _day, [
        for (final r in _roster) {'student_id': r.studentId, 'status': _status[r.studentId] ?? 'present'},
      ]);
      if (mounted) notify(context, 'Attendance saved.');
      await _load();
    } catch (e) {
      if (mounted) notify(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  int _count(String s) => _status.values.where((v) => v == s).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (_loading) return const LoadingView();
    if (_error != null) {
      return MessageView(icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load);
    }
    if (_noYear) {
      return const MessageView(
        icon: Icons.event_busy_outlined,
        title: 'No current school year',
        message: 'The administrator must mark a school year as current before attendance can be taken.',
      );
    }
    final canBack = widget.isAdmin || _day.isAfter(_today.subtract(const Duration(days: 7)));
    final canForward = _day.isBefore(_today);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(children: [
          IconButton(onPressed: canBack ? () => _shift(-1) : null, icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: InkWell(
              onTap: _pick,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(children: [
                  Text('${_weekdays[_day.weekday - 1]}, ${formatDate(_day)}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text(_day == _today ? 'Today' : 'Tap to pick a date',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
          IconButton(onPressed: canForward ? () => _shift(1) : null, icon: const Icon(Icons.chevron_right)),
        ]),
      ),
      Expanded(
        child: _roster.isEmpty
            ? const MessageView(
                icon: Icons.groups_outlined,
                title: 'No students in this class',
                message: 'Students must be put in this class for the current school year first.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                children: [
                  if (!_hasRecords)
                    const HintBanner(text: 'Not saved yet for this day. Everyone is set to Present until you save.'),
                  if (!widget.isAdmin)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('You can mark today and the last 7 days. Ask the administrator to change older days.',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: Text('Present ${_count('present')}  ·  Late ${_count('late')}  ·  Absent ${_count('absent')}',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                for (final r in _roster) {
                                  _status[r.studentId] = 'present';
                                }
                              }),
                      child: const Text('All present'),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  for (final r in _roster) ...[
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        Text(r.admissionNumber,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            showSelectedIcon: false,
                            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                            segments: [
                              for (final s in const ['present', 'late', 'absent'])
                                ButtonSegment(
                                  value: s,
                                  label: Text(s[0].toUpperCase() + s.substring(1)),
                                ),
                            ],
                            selected: {_status[r.studentId] ?? 'present'},
                            onSelectionChanged: _busy ? null : (v) => setState(() => _status[r.studentId] = v.first),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
      ),
      if (_roster.isNotEmpty)
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_hasRecords ? 'Update attendance' : 'Save attendance'),
            ),
          ),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ records

class _RecordsTab extends StatefulWidget {
  const _RecordsTab({super.key, required this.school, required this.classId});

  final School school;
  final String classId;

  @override
  State<_RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends State<_RecordsTab> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<RosterEntry> _roster = const [];
  Map<String, Map<String, int>> _counts = {};
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
      final sid = await SetupRepository.instance.currentSessionId(widget.school.id);
      final roster = sid == null ? <RosterEntry>[] : await TeacherRepository.instance.roster(widget.classId, sid);
      final last = DateTime(_month.year, _month.month + 1, 0);
      final records = await AttendanceRepository.instance.forClassRange(widget.classId, _month, last);
      final counts = <String, Map<String, int>>{};
      for (final r in records) {
        final m = counts.putIfAbsent(r.studentId, () => {'present': 0, 'late': 0, 'absent': 0});
        m[r.status] = (m[r.status] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() {
        _roster = roster;
        _counts = counts;
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

  void _shift(int months) {
    final next = DateTime(_month.year, _month.month + months);
    if (next.isAfter(DateTime(DateTime.now().year, DateTime.now().month))) return;
    setState(() => _month = next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final atCurrent = _month.year == DateTime.now().year && _month.month == DateTime.now().month;

    final totalP = _counts.values.fold<int>(0, (s, m) => s + (m['present'] ?? 0));
    final totalL = _counts.values.fold<int>(0, (s, m) => s + (m['late'] ?? 0));
    final totalA = _counts.values.fold<int>(0, (s, m) => s + (m['absent'] ?? 0));
    final marked = totalP + totalL + totalA;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(children: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text('${_monthNames[_month.month - 1]} ${_month.year}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          IconButton(onPressed: atCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
        ]),
      ),
      Expanded(
        child: _loading
            ? const LoadingView()
            : _error != null
                ? MessageView(icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load)
                : _roster.isEmpty
                    ? const MessageView(
                        icon: Icons.groups_outlined,
                        title: 'No students',
                        message: 'No students are in this class for the current school year.')
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: [
                          AppCard(
                            child: Row(children: [
                              _stat('Present', totalP, statusColor('present')),
                              _stat('Late', totalL, statusColor('late')),
                              _stat('Absent', totalA, statusColor('absent')),
                              _stat('Marked', marked, cs.onSurfaceVariant),
                            ]),
                          ),
                          const SizedBox(height: 12),
                          if (marked == 0)
                            const HintBanner(text: 'No attendance was saved for this month yet.')
                          else
                            for (final r in _roster) ...[
                              _studentRow(r),
                              const SizedBox(height: 10),
                            ],
                        ],
                      ),
      ),
    ]);
  }

  Widget _stat(String label, int v, Color c) => Expanded(
        child: Column(children: [
          Text('$v', style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  Widget _studentRow(RosterEntry r) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = _counts[r.studentId] ?? const {'present': 0, 'late': 0, 'absent': 0};
    final days = (m['present'] ?? 0) + (m['late'] ?? 0) + (m['absent'] ?? 0);
    final attended = (m['present'] ?? 0) + (m['late'] ?? 0);
    return AppCard(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            Text('Present ${m['present']}  ·  Late ${m['late']}  ·  Absent ${m['absent']}',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        Text(days == 0 ? '-' : '${(attended * 100 / days).round()}%',
            style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: days == 0 ? cs.onSurfaceVariant : (attended / days >= 0.75 ? AppTheme.green : statusColor('absent')))),
      ]),
    );
  }
}
