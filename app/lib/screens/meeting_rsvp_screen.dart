import 'package:flutter/material.dart';

import '../data/meetings_repository.dart';
import '../data/models.dart';
import '../data/school_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/state_views.dart';

/// Administrator: who is coming to a meeting.
class MeetingRsvpScreen extends StatefulWidget {
  const MeetingRsvpScreen({super.key, required this.meeting});

  final MeetingItem meeting;

  @override
  State<MeetingRsvpScreen> createState() => _MeetingRsvpScreenState();
}

class _MeetingRsvpScreenState extends State<MeetingRsvpScreen> {
  List<RsvpRow> _rows = const [];
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
      final rows = await MeetingsRepository.instance.rsvpReport(widget.meeting.id);
      if (!mounted) return;
      setState(() {
        _rows = rows;
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
    final theme = Theme.of(context);
    int count(String r) => _rows.where((x) => x.response == r).length;
    Color color(String r) => switch (r) {
          'attending' => AppTheme.green,
          'not_attending' => const Color(0xFFC62828),
          _ => Colors.grey,
        };
    String label(String r) => switch (r) {
          'attending' => 'Coming',
          'not_attending' => 'Cannot come',
          _ => 'No answer',
        };
    return Scaffold(
      appBar: AppBar(title: const Text('Responses')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? MessageView(icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Text(widget.meeting.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      Text(widget.meeting.whenLabel, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 12),
                      AppCard(
                        child: Row(children: [
                          for (final r in const ['attending', 'not_attending', 'no_response'])
                            Expanded(
                              child: Column(children: [
                                Text('${count(r)}', style: TextStyle(color: color(r), fontSize: 24, fontWeight: FontWeight.bold)),
                                Text(label(r), style: theme.textTheme.bodySmall),
                              ]),
                            ),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      for (final r in _rows) ...[
                        AppCard(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(children: [
                            Expanded(child: Text(r.parentName, style: theme.textTheme.titleSmall)),
                            StatusPill(label: label(r.response), color: color(r.response)),
                          ]),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
    );
  }
}
