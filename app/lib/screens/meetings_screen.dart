import 'package:flutter/material.dart';

import '../data/meetings_repository.dart';
import '../data/models.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../data/setup_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';
import '../widgets/help.dart';
import '../widgets/state_views.dart';
import 'meeting_rsvp_screen.dart';

/// Parent-teacher meetings. Administrators schedule them, parents say if they are coming,
/// teachers can see the ones that concern them.
class MeetingsScreen extends StatefulWidget {
  const MeetingsScreen({super.key, required this.school, required this.member});

  final School school;
  final Member member;

  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen> {
  List<MeetingItem> _items = const [];
  Map<String, String> _answers = const {};
  bool _loading = true;
  String? _error;

  bool get _isAdmin => widget.member.role == 'school_admin';
  bool get _isParent => widget.member.isParent;

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
      final repo = MeetingsRepository.instance;
      final items = await repo.list(widget.school.id);
      final answers = _isParent ? await repo.myResponses() : <String, String>{};
      if (!mounted) return;
      setState(() {
        _items = items;
        _answers = answers;
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

  Future<void> _answer(MeetingItem m, String response) async {
    try {
      await MeetingsRepository.instance.respond(m.id, response);
      if (!mounted) return;
      notify(context, response == 'attending' ? 'Thank you. We will expect you.' : 'Thanks for letting the school know.');
      await _load();
    } catch (e) {
      if (mounted) notify(context, friendlyError(e), error: true);
    }
  }

  Future<void> _edit([MeetingItem? m]) async {
    List<ClassRow> classes;
    try {
      classes = await SetupRepository.instance.classes(widget.school.id);
    } catch (e) {
      if (mounted) notify(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    final ok = await showFormSheet(
      context,
      title: m == null ? 'New meeting' : 'Edit meeting',
      subtitle: 'The parents it is for, and the teachers, are notified.',
      submitLabel: 'Save meeting',
      fields: [
        FieldSpec('title', 'Title', required: true, initial: m?.title, hint: 'Parent-teacher meeting'),
        FieldSpec('desc', 'Details (optional)', kind: FieldKind.multiline, initial: m?.description),
        FieldSpec('date', 'Date', kind: FieldKind.date, required: true, initial: m == null ? '' : isoDate(m.startsAt)),
        FieldSpec('start', 'Starts at', kind: FieldKind.time, required: true, initial: m == null ? '' : formatTime(m.startsAt)),
        FieldSpec('end', 'Ends at', kind: FieldKind.time, required: true, initial: m == null ? '' : formatTime(m.endsAt)),
        FieldSpec('where', 'Where? (optional)', initial: m?.location, hint: 'School hall'),
        FieldSpec('class', 'Only for one class? (optional)',
            kind: FieldKind.choice, hint: 'All parents', initial: m?.classId ?? '',
            options: [for (final c in classes) (c.id, c.name)]),
      ],
      onSubmit: (v) async {
        DateTime at(String time) {
          final d = DateTime.parse(v['date']!);
          final p = time.split(':');
          return DateTime(d.year, d.month, d.day, int.parse(p[0]), int.parse(p[1]));
        }

        final start = at(v['start']!);
        final end = at(v['end']!);
        if (!end.isAfter(start)) throw FormError('The end time must be after the start time.');
        if (m == null && start.isBefore(DateTime.now())) throw FormError('Choose a time in the future.');
        try {
          await MeetingsRepository.instance.save(
            id: m?.id,
            schoolId: widget.school.id,
            title: v['title']!,
            description: v['desc']!.isEmpty ? null : v['desc'],
            startsAt: start,
            endsAt: end,
            location: v['where']!.isEmpty ? null : v['where'],
            classId: v['class']!.isEmpty ? null : v['class'],
          );
        } catch (e) {
          throw FormError(friendlyError(e));
        }
      },
    );
    if (ok == true) await _load();
  }

  Future<void> _cancel(MeetingItem m) async {
    final ok = await confirmDialog(context,
        title: 'Cancel this meeting?',
        message: 'Parents and teachers will be told it was cancelled.',
        action: 'Cancel meeting',
        destructive: true);
    if (!ok) return;
    try {
      await MeetingsRepository.instance.cancel(m.id);
      await _load();
    } catch (e) {
      if (mounted) notify(context, friendlyError(e), error: true);
    }
  }

  Widget _card(MeetingItem m) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final answer = _answers[m.id];
    final open = !m.isCancelled && !m.isOver;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(m.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          if (m.isCancelled) StatusPill(label: 'Cancelled', color: cs.error),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Icon(Icons.event, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(m.whenLabel, style: theme.textTheme.bodyMedium)),
        ]),
        if ((m.location ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              Icon(Icons.place_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(child: Text(m.location!, style: theme.textTheme.bodyMedium)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(m.className == null ? 'For all parents' : 'For parents of ${m.className}',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        if ((m.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(m.description!, style: theme.textTheme.bodyMedium),
        ],
        if (_isParent && open) ...[
          const SizedBox(height: 12),
          Text(answer == null ? 'Will you come?' : (answer == 'attending' ? 'You said you will come.' : 'You said you cannot come.'),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'attending', label: Text('I will come'), icon: Icon(Icons.check)),
                ButtonSegment(value: 'not_attending', label: Text('Cannot come'), icon: Icon(Icons.close)),
              ],
              selected: answer == null ? <String>{} : {answer},
              onSelectionChanged: (s) {
                if (s.isNotEmpty) _answer(m, s.first);
              },
            ),
          ),
        ],
        if (_isAdmin) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MeetingRsvpScreen(meeting: m))),
              icon: const Icon(Icons.people_outline),
              label: const Text('Responses'),
            ),
            if (open) TextButton.icon(onPressed: () => _edit(m), icon: const Icon(Icons.edit_outlined), label: const Text('Edit')),
            if (open) TextButton.icon(onPressed: () => _cancel(m), icon: const Icon(Icons.event_busy_outlined), label: const Text('Cancel')),
          ]),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = _items.where((m) => !m.isOver).toList();
    final past = _items.where((m) => m.isOver).toList().reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meetings'),
        actions: [
          HelpButton(
            title: 'Meetings',
            steps: _isAdmin
                ? const [
                    'Tap "New meeting", pick the date and times, and choose a class if it is only for one class.',
                    'Parents (and the teachers concerned) get a notification.',
                    'Tap "Responses" to see who is coming. If you edit or cancel, they are told again.',
                  ]
                : const [
                    'Upcoming meetings from your school are listed here.',
                    'Parents: tap "I will come" or "Cannot come". You can change your answer until the meeting.',
                  ],
          ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('New meeting'))
          : null,
      body: _loading
          ? const LoadingView()
          : _error != null
              ? MessageView(icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? MessageView(
                      icon: Icons.groups_outlined,
                      title: 'No meetings',
                      message: _isAdmin ? 'Tap "New meeting" to schedule one.' : 'When the school schedules a meeting, it will appear here.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, _isAdmin ? 100 : 24),
                        children: [
                          if (upcoming.isNotEmpty) const SectionTitle('Upcoming'),
                          for (final m in upcoming) ...[_card(m), const SizedBox(height: 10)],
                          if (past.isNotEmpty) const SectionTitle('Past'),
                          for (final m in past) ...[_card(m), const SizedBox(height: 10)],
                        ],
                      ),
                    ),
    );
  }
}
