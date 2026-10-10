import 'package:flutter/material.dart';

import '../data/admin_repository.dart';
import '../data/models.dart';
import '../data/school_repository.dart';
import '../widgets/state_views.dart';

/// Administrator's announcement manager: write, publish, archive, delete.
class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key, required this.schoolId});

  final String schoolId;

  @override
  State<AdminAnnouncementsScreen> createState() => _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  List<Announcement> _items = const [];
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
      final list = await AdminRepository.instance.announcements(widget.schoolId);
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

  Future<void> _edit([Announcement? a]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _Editor(schoolId: widget.schoolId, existing: a),
    );
    if (saved == true) _load();
  }

  Color _statusColor(String s) => switch (s) {
        'published' => const Color(0xFF1B8A5A),
        'archived' => Colors.grey,
        _ => const Color(0xFFE07B00),
      };

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return MessageView(
          icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return const MessageView(
        icon: Icons.campaign_outlined,
        title: 'No announcements yet',
        message: 'Tap New to write the first one.',
      );
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final a = _items[i];
          final color = _statusColor(a.status);
          return Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _edit(a),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(a.title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text(a.status,
                          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('For: ${a.audience}${a.publishedAt == null ? '' : '  ·  ${formatDate(a.publishedAt)}'}',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Text(a.body, maxLines: 2, overflow: TextOverflow.ellipsis),
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
    return Stack(children: [
      _body(),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('New'),
        ),
      ),
    ]);
  }
}

class _Editor extends StatefulWidget {
  const _Editor({required this.schoolId, this.existing});

  final String schoolId;
  final Announcement? existing;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  static const _audiences = [
    ('all', 'Everyone'),
    ('students', 'Students'),
    ('parents', 'Parents'),
    ('staff', 'Staff'),
  ];
  static const _statuses = [
    ('draft', 'Draft'),
    ('published', 'Published'),
    ('archived', 'Archived'),
  ];

  late final TextEditingController _title;
  late final TextEditingController _body;
  late String _audience;
  late String _status;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _title = TextEditingController(text: a?.title ?? '');
    _body = TextEditingController(text: a?.body ?? '');
    _audience = a?.audience ?? 'all';
    _status = a?.status ?? 'published';
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(() => _error = 'Please write a title and a message.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminRepository.instance.saveAnnouncement(
        id: widget.existing?.id,
        schoolId: widget.schoolId,
        title: title,
        body: body,
        audience: _audience,
        status: _status,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _busy = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: const Text('This cannot be undone. To keep it, archive it instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await AdminRepository.instance.deleteAnnouncement(widget.existing!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.existing == null ? 'New announcement' : 'Edit announcement',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Message'),
          ),
          const SizedBox(height: 16),
          Text('Who should see it?', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final a in _audiences)
              ChoiceChip(
                label: Text(a.$2),
                selected: _audience == a.$1,
                onSelected: (_) => setState(() => _audience = a.$1),
              ),
          ]),
          const SizedBox(height: 14),
          Text('Status', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final s in _statuses)
              ChoiceChip(
                label: Text(s.$2),
                selected: _status == s.$1,
                onSelected: (_) => setState(() => _status = s.$1),
              ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Save'),
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _delete,
              child: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
            ),
          ],
        ]),
      ),
    );
  }
}
