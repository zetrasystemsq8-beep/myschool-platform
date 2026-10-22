import 'package:flutter/material.dart';

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

const _graduate = '__graduate__';
const _none = '__none__';

/// Start a new school year: move each class up to the next one (or graduate it),
/// choose who repeats, keep the teachers, and make the new year current.
class NewSchoolYearScreen extends StatefulWidget {
  const NewSchoolYearScreen({super.key, required this.school});

  final School school;

  @override
  State<NewSchoolYearScreen> createState() => _NewSchoolYearScreenState();
}

class _NewSchoolYearScreenState extends State<NewSchoolYearScreen> {
  List<SessionInfo> _sessions = const [];
  List<ClassRow> _classes = const [];
  Map<String, int> _counts = {};
  final Map<String, String> _dest = {}; // classId -> class id | _graduate | _none
  final Map<String, Set<String>> _repeat = {};
  String? _from;
  String? _to;
  bool _copyTeachers = true;
  bool _makeCurrent = true;
  bool _loading = true;
  bool _running = false;
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
      final repo = SetupRepository.instance;
      final sessions = await repo.sessions(widget.school.id);
      final classes = await repo.classes(widget.school.id);
      String? from;
      String? to;
      if (sessions.length >= 2) {
        to = sessions.first.id; // newest school year
        final current = sessions.where((s) => s.isCurrent).map((s) => s.id).firstOrNull;
        from = (current != null && current != to) ? current : sessions[1].id;
      }
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _classes = classes;
        _from = from;
        _to = to;
      });
      await _loadCounts();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  /// "JSS 1 A" -> "JSS 2 A" if that class exists.
  String _suggest(ClassRow c) {
    final m = RegExp(r'\d+').firstMatch(c.name);
    if (m == null) return _none;
    final next = c.name.replaceRange(m.start, m.end, '${int.parse(m.group(0)!) + 1}');
    final hit = _classes.where((x) => x.name.toLowerCase() == next.toLowerCase());
    return hit.isEmpty ? _none : hit.first.id;
  }

  Future<void> _loadCounts() async {
    final from = _from;
    if (from == null) return;
    final counts = await SetupRepository.instance.activeCounts(from);
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _dest.clear();
      _repeat.clear();
      for (final c in _classes) {
        if ((counts[c.id] ?? 0) > 0) _dest[c.id] = _suggest(c);
      }
    });
  }

  String _sessionName(String? id) => _sessions.where((s) => s.id == id).map((s) => s.name).firstOrNull ?? 'Choose';

  Future<void> _pickSession({required bool from}) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(from ? 'Move students FROM' : 'Move students TO', style: Theme.of(ctx).textTheme.titleMedium),
            ),
          ),
          for (final s in _sessions)
            ListTile(
              title: Text(s.name),
              trailing: s.isCurrent ? const Chip(label: Text('Current'), visualDensity: VisualDensity.compact) : null,
              onTap: () => Navigator.pop(ctx, s.id),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked == null) return;
    setState(() => from ? _from = picked : _to = picked);
    if (from) await _loadCounts();
  }

  String _destLabel(String value) {
    if (value == _graduate) return 'Graduates (leaves the school)';
    if (value == _none) return 'Not moving yet';
    return _classes.where((c) => c.id == value).map((c) => 'Moves to ${c.name}').firstOrNull ?? 'Choose';
  }

  Future<void> _pickDest(ClassRow c) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Where does ${c.name} go?', style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ListTile(leading: const Icon(Icons.school_outlined), title: const Text('Graduates (leaves the school)'), onTap: () => Navigator.pop(ctx, _graduate)),
            ListTile(leading: const Icon(Icons.pause_circle_outline), title: const Text('Not moving yet'), onTap: () => Navigator.pop(ctx, _none)),
            const Divider(),
            for (final x in _classes) ListTile(title: Text(x.name), onTap: () => Navigator.pop(ctx, x.id)),
          ]),
        ),
      ),
    );
    if (picked != null) setState(() => _dest[c.id] = picked);
  }

  Future<void> _pickRepeaters(ClassRow c) async {
    try {
      final roster = await TeacherRepository.instance.roster(c.id, _from!);
      if (!mounted) return;
      final chosen = {...(_repeat[c.id] ?? <String>{})};
      final result = await showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text('Who repeats ${c.name}?', style: Theme.of(ctx).textTheme.titleMedium),
                ),
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final r in roster)
                      CheckboxListTile(
                        value: chosen.contains(r.studentId),
                        title: Text(r.name),
                        subtitle: Text(r.admissionNumber),
                        onChanged: (v) => setSheet(() => v == true ? chosen.add(r.studentId) : chosen.remove(r.studentId)),
                      ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: FilledButton(onPressed: () => Navigator.pop(ctx, chosen), child: const Text('Done')),
                ),
              ]),
            ),
          ),
        ),
      );
      if (result != null) setState(() => _repeat[c.id] = result);
    } catch (e) {
      if (mounted) notify(context, friendlyError(e), error: true);
    }
  }

  Future<void> _run() async {
    final from = _from, to = _to;
    if (from == null || to == null) return;
    if (from == to) {
      notify(context, 'Choose two different school years.', error: true);
      return;
    }
    final moving = _classes.where((c) => (_counts[c.id] ?? 0) > 0 && _dest[c.id] != _none).toList();
    if (moving.isEmpty) {
      notify(context, 'Choose where at least one class goes.', error: true);
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Move students up?',
        message: 'This moves the students of ${moving.length} class${moving.length == 1 ? '' : 'es'} from ${_sessionName(from)} to ${_sessionName(to)}. '
            'You can run it again for the classes you left out.',
        action: 'Move students');
    if (!ok) return;

    setState(() => _running = true);
    final repo = SetupRepository.instance;
    var promoted = 0, repeated = 0, graduated = 0, skipped = 0;
    final failures = <String>[];
    for (final c in moving) {
      try {
        final d = _dest[c.id]!;
        final r = await repo.promoteClass(
          fromSession: from,
          toSession: to,
          fromClass: c.id,
          toClass: d == _graduate ? null : d,
          repeaters: (_repeat[c.id] ?? <String>{}).toList(),
        );
        promoted += r['promoted'] ?? 0;
        repeated += r['repeated'] ?? 0;
        graduated += r['graduated'] ?? 0;
        skipped += r['skipped'] ?? 0;
      } catch (e) {
        failures.add('${c.name}: ${friendlyError(e)}');
      }
    }
    var teachers = 0;
    if (_copyTeachers) {
      try {
        teachers = await repo.copyAssignments(from, to);
      } catch (e) {
        failures.add('Teachers: ${friendlyError(e)}');
      }
    }
    if (_makeCurrent && failures.isEmpty) {
      try {
        await repo.setCurrentSession(widget.school.id, to);
      } catch (e) {
        failures.add('Current year: ${friendlyError(e)}');
      }
    }
    if (!mounted) return;
    setState(() => _running = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(failures.isEmpty ? 'Done' : 'Finished with problems'),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Moved up: $promoted'),
            Text('Repeating: $repeated'),
            Text('Graduated: $graduated'),
            if (skipped > 0) Text('Already in the new year: $skipped'),
            if (_copyTeachers) Text('Teacher assignments kept: $teachers'),
            if (failures.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Problems:', style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontWeight: FontWeight.bold)),
              for (final f in failures) Text(f),
            ],
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final classesWithStudents = _classes.where((c) => (_counts[c.id] ?? 0) > 0).toList();

    Widget body;
    if (_loading) {
      body = const LoadingView();
    } else if (_error != null) {
      body = MessageView(icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load);
    } else if (_sessions.length < 2) {
      body = const MessageView(
        icon: Icons.event_note_outlined,
        title: 'Add the new school year first',
        message: 'Go to School years & terms and add the new year (and its terms). Then come back here to move the students up.',
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const HintBanner(
            text: 'Step 1: choose the old and the new school year. Step 2: choose where each class goes. Step 3: tap "Move students up".',
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _yearTile('From', _sessionName(_from), () => _pickSession(from: true))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward)),
            Expanded(child: _yearTile('To', _sessionName(_to), () => _pickSession(from: false))),
          ]),
          const SectionTitle('Classes'),
          if (classesWithStudents.isEmpty)
            const HintBanner(text: 'No active students are in a class for the "From" year. Put students in classes first, or pick another year.'),
          for (final c in classesWithStudents) ...[
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(c.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                  Text('${_counts[c.id]} students', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _pickDest(c),
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Where do they go?', suffixIcon: Icon(Icons.arrow_drop_down)),
                    child: Text(_destLabel(_dest[c.id] ?? _none)),
                  ),
                ),
                if (_dest[c.id] != _none)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _pickRepeaters(c),
                      icon: const Icon(Icons.replay, size: 18),
                      label: Text('Students who repeat (${(_repeat[c.id] ?? {}).length})'),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep the same teachers'),
                subtitle: const Text('Copy each teacher\'s classes and subjects to the new year.'),
                value: _copyTeachers,
                onChanged: (v) => setState(() => _copyTeachers = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Make the new year the current one'),
                value: _makeCurrent,
                onChanged: (v) => setState(() => _makeCurrent = v),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _running || classesWithStudents.isEmpty ? null : _run,
            icon: _running
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.trending_up),
            label: Text(_running ? 'Moving students...' : 'Move students up'),
          ),
          const SizedBox(height: 10),
          Text('Old results, attendance and fees stay exactly as they were. You can run this again for classes you left out.',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      );
    }

    return PopScope(
      canPop: !_running,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New school year'),
          actions: const [
            HelpButton(
              title: 'New school year',
              intro: 'Moves your students into the next year in a few taps.',
              steps: [
                'First add the new school year and its terms under "School years & terms".',
                'Here, choose the old year ("From") and the new one ("To").',
                'For each class choose where it goes. Classes like JSS 1 A are suggested JSS 2 A when that class exists.',
                'Tap "Students who repeat" for anyone staying in the same class.',
                'Choose "Graduates" for your final class. They can still sign in to see their old results.',
              ],
            ),
          ],
        ),
        body: body,
      ),
    );
  }

  Widget _yearTile(String label, String value, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: AppTheme.green)),
      ]),
    );
  }
}
