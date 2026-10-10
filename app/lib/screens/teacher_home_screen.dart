import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/models.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../data/teacher_repository.dart';
import '../widgets/state_views.dart';
import 'result_entry_screen.dart';

/// "My classes": the class + subject pairs the admin assigned to this teacher.
class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key, required this.school});

  final School school;

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  List<Assignment> _items = const [];
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
      final uid = AuthRepository.instance.userId!;
      final list = await TeacherRepository.instance.assignments(uid, widget.school.id);
      if (!mounted) return;
      setState(() {
        _items = list;
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

  Future<void> _pickTerm(Assignment a) async {
    try {
      final terms = await TeacherRepository.instance.terms(widget.school.id, a.sessionId);
      if (!mounted) return;
      if (terms.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No terms are set up for this session yet. Ask your administrator.')));
        return;
      }
      final chosen = await showModalBottomSheet<TermInfo>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('${a.className} · ${a.subjectName}',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final t in terms)
              ListTile(
                title: Text('${t.name}  (${a.sessionName})'),
                trailing: t.isCurrent
                    ? const Chip(label: Text('Current'), visualDensity: VisualDensity.compact)
                    : const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, t),
              ),
            const SizedBox(height: 12),
          ]),
        ),
      );
      if (chosen == null || !mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ResultEntryScreen(school: widget.school, assignment: a, term: chosen),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return MessageView(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your classes',
          message: _error!,
          onRetry: _load);
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 120),
          MessageView(
            icon: Icons.class_outlined,
            title: 'No classes assigned yet',
            message: 'Your administrator assigns the classes and subjects you teach.',
          ),
        ]),
      );
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final a = _items[i];
          return Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _pickTerm(a),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  CircleAvatar(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    child: Text(a.subjectCode.isEmpty
                        ? '?'
                        : (a.subjectCode.length > 3 ? a.subjectCode.substring(0, 3) : a.subjectCode)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.subjectName,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('${a.className}  ·  ${a.sessionName}',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  Icon(Icons.edit_note, color: cs.primary),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
