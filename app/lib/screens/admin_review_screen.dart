import 'package:flutter/material.dart';

import '../data/admin_repository.dart';
import '../data/models.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../widgets/state_views.dart';
import 'sheet_review_screen.dart';

/// Administrator's list of result sheets by stage.
class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({super.key, required this.school});

  final School school;

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen> {
  static const _filters = [
    ('submitted', 'To review'),
    ('approved', 'Approved'),
    ('published', 'Published'),
  ];

  String _status = 'submitted';
  List<SheetSummary> _items = const [];
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
      final list = await AdminRepository.instance.sheets(widget.school.id, _status);
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

  Future<void> _open(SheetSummary s) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SheetReviewScreen(school: widget.school, sheet: s)),
    );
    if (mounted) _load();
  }

  Widget _list() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return MessageView(
          icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 100),
          MessageView(
            icon: Icons.inbox_outlined,
            title: 'Nothing here',
            message: 'Sheets at this stage will appear here.',
          ),
        ]),
      );
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final s = _items[i];
          return Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _open(s),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s.subjectName} · ${s.className}',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('${s.termName}  ·  ${s.sessionName}',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          children: [
            for (final f in _filters) ...[
              ChoiceChip(
                label: Text(f.$2),
                selected: _status == f.$1,
                onSelected: (_) {
                  setState(() => _status = f.$1);
                  _load();
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
      Expanded(child: _list()),
    ]);
  }
}
