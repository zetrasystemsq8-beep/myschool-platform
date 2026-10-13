import 'package:flutter/material.dart';

import '../data/attendance_repository.dart';
import '../data/models.dart';
import '../data/school_repository.dart';
import '../widgets/app_card.dart';
import '../widgets/help.dart';
import '../widgets/state_views.dart';
import 'attendance_screen.dart' show statusColor;

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A student's (or a parent's child's) own attendance, month by month.
class AttendanceViewScreen extends StatefulWidget {
  const AttendanceViewScreen({super.key, required this.student});

  final StudentInfo? student;

  @override
  State<AttendanceViewScreen> createState() => _AttendanceViewScreenState();
}

class _AttendanceViewScreenState extends State<AttendanceViewScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<AttendanceRecord> _records = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = widget.student;
    if (s == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final last = DateTime(_month.year, _month.month + 1, 0);
      final list = await AttendanceRepository.instance.forStudentRange(s.id, _month, last);
      if (!mounted) return;
      setState(() {
        _records = list;
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
    if (widget.student == null) {
      return const MessageView(
        icon: Icons.person_search_outlined,
        title: 'No student linked',
        message: 'This account is not linked to a student yet. Please contact your school.',
      );
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final atCurrent = _month.year == DateTime.now().year && _month.month == DateTime.now().month;
    int count(String s) => _records.where((r) => r.status == s).length;
    final days = _records.length;
    final attended = count('present') + count('late');

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
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        Text(widget.student!.fullName,
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        AppCard(
                          child: Row(children: [
                            _stat('Present', count('present'), statusColor('present')),
                            _stat('Late', count('late'), statusColor('late')),
                            _stat('Absent', count('absent'), statusColor('absent')),
                            _stat('Attended', days == 0 ? 0 : (attended * 100 / days).round(), cs.primary, suffix: '%'),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        if (_records.isEmpty)
                          const HintBanner(text: 'No attendance has been recorded for this month yet.')
                        else
                          for (final r in _records) ...[
                            AppCard(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(children: [
                                Icon(
                                  r.status == 'present'
                                      ? Icons.check_circle
                                      : (r.status == 'late' ? Icons.schedule : Icons.cancel),
                                  color: statusColor(r.status),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text('${_weekdays[r.date.weekday - 1]}, ${formatDate(r.date)}',
                                      style: theme.textTheme.bodyMedium),
                                ),
                                StatusPill(label: r.label, color: statusColor(r.status)),
                              ]),
                            ),
                            const SizedBox(height: 8),
                          ],
                      ],
                    ),
                  ),
      ),
    ]);
  }

  Widget _stat(String label, int v, Color c, {String suffix = ''}) => Expanded(
        child: Column(children: [
          Text('$v$suffix', style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}
