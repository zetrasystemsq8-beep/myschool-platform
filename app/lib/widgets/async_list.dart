import 'package:flutter/material.dart';

import '../data/school_repository.dart';
import 'state_views.dart';

/// Loading / error / empty / pull-to-refresh list with an optional "add" button.
/// Every setup screen uses this, so they all behave the same way.
class AsyncList<T> extends StatefulWidget {
  const AsyncList({
    super.key,
    required this.load,
    required this.itemBuilder,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    this.onAdd,
    this.addLabel = 'Add',
  });

  final Future<List<T>> Function() load;

  /// [reload] refreshes the list after an item action changed something.
  final Widget Function(BuildContext context, T item, Future<void> Function() reload) itemBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  /// Return true when something was created so the list reloads.
  final Future<bool?> Function()? onAdd;
  final String addLabel;

  @override
  State<AsyncList<T>> createState() => _AsyncListState<T>();
}

class _AsyncListState<T> extends State<AsyncList<T>> {
  List<T> _items = <T>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await widget.load();
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

  Future<void> _add() async {
    final changed = await widget.onAdd!();
    if (changed == true) await _load();
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return MessageView(
          icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          const SizedBox(height: 90),
          MessageView(icon: widget.emptyIcon, title: widget.emptyTitle, message: widget.emptyMessage),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 8, 16, widget.onAdd == null ? 24 : 100),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) => widget.itemBuilder(ctx, _items[i], _load),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: _body()),
      if (widget.onAdd != null)
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: Text(widget.addLabel),
          ),
        ),
    ]);
  }
}
