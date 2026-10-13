import 'package:flutter/material.dart';

import '../data/fees_repository.dart';
import '../data/models.dart';
import '../data/school_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';
import '../widgets/help.dart';
import '../widgets/state_views.dart';

Color feeStatusColor(String status) => switch (status) {
      'paid' => AppTheme.green,
      'part_paid' => const Color(0xFFE07B00),
      'overdue' => const Color(0xFFC62828),
      _ => Colors.grey,
    };

/// Parents: what is due, what was paid, what is still owed.
/// Money shown here was RECORDED BY THE SCHOOL. Online payment is not available.
class FeesScreen extends StatefulWidget {
  const FeesScreen({super.key, required this.student});

  final StudentInfo? student;

  @override
  State<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends State<FeesScreen> {
  List<FeeBalance> _fees = const [];
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
      final list = await FeesRepository.instance.forStudent(s.id);
      if (!mounted) return;
      setState(() {
        _fees = list;
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
    if (widget.student == null) {
      return const MessageView(
        icon: Icons.person_search_outlined,
        title: 'No student linked',
        message: 'This account is not linked to a student yet. Please contact your school.',
      );
    }
    if (_loading) return const LoadingView();
    if (_error != null) {
      return MessageView(icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load);
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currency = _fees.isEmpty ? 'NGN' : _fees.first.currency;
    final due = _fees.fold<double>(0, (s, f) => s + f.amount);
    final paid = _fees.fold<double>(0, (s, f) => s + f.paid);
    final owed = _fees.fold<double>(0, (s, f) => s + (f.balance > 0 ? f.balance : 0));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(widget.student!.fullName,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (_fees.isEmpty)
            const MessageView(
              icon: Icons.receipt_long_outlined,
              title: 'No fees yet',
              message: 'Fees set by the school for this student will appear here.',
            )
          else ...[
            AppCard(
              child: Row(children: [
                _stat('Total due', money(due, currency), cs.onSurface),
                _stat('Paid', money(paid, currency), AppTheme.green),
                _stat('Outstanding', money(owed, currency), owed > 0 ? const Color(0xFFC62828) : AppTheme.green),
              ]),
            ),
            const SizedBox(height: 10),
            const HintBanner(
              icon: Icons.info_outline,
              text: 'Payments are recorded by the school office when money is received. Keep your receipt. '
                  'Online payment is not available yet.',
            ),
            const SizedBox(height: 12),
            for (final f in _fees) ...[
              _FeeCard(fee: f, onTap: () => showPaymentsSheet(context, f)),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Column(children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

class _FeeCard extends StatelessWidget {
  const _FeeCard({required this.fee, required this.onTap});

  final FeeBalance fee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = feeStatusColor(fee.status);
    final sub = [fee.categoryName, if ((fee.termName ?? '').isNotEmpty) fee.termName!, fee.sessionName]
        .where((e) => e.isNotEmpty)
        .join('  ·  ');
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(fee.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          StatusPill(label: fee.statusLabel, color: color),
        ]),
        const SizedBox(height: 2),
        Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        if (fee.dueDate != null)
          Text('Due ${fee.dueDate}', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fee.amount <= 0 ? 0 : (fee.paid / fee.amount).clamp(0.0, 1.0),
            minHeight: 8,
            color: AppTheme.green,
            backgroundColor: AppTheme.green.withValues(alpha: 0.14),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('Paid ${money(fee.paid, fee.currency)} of ${money(fee.amount, fee.currency)}',
              style: theme.textTheme.bodySmall)),
          Text(fee.balance > 0 ? 'Owes ${money(fee.balance, fee.currency)}' : 'Cleared',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
        ]),
      ]),
    );
  }
}

/// Payment history for one fee. Admins can also reverse a payment they recorded by mistake.
Future<void> showPaymentsSheet(BuildContext context, FeeBalance fee,
    {bool admin = false, VoidCallback? onChanged}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PaymentsSheet(fee: fee, admin: admin, onChanged: onChanged),
  );
}

class _PaymentsSheet extends StatefulWidget {
  const _PaymentsSheet({required this.fee, required this.admin, this.onChanged});

  final FeeBalance fee;
  final bool admin;
  final VoidCallback? onChanged;

  @override
  State<_PaymentsSheet> createState() => _PaymentsSheetState();
}

class _PaymentsSheetState extends State<_PaymentsSheet> {
  List<FeePayment> _payments = const [];
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
      final list = await FeesRepository.instance.payments(widget.fee.studentFeeId);
      if (!mounted) return;
      setState(() {
        _payments = list;
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

  Future<void> _reverse(FeePayment p) async {
    final ok = await showFormSheet(
      context,
      title: 'Reverse this payment?',
      subtitle: '${money(p.amount, widget.fee.currency)} on ${p.paidOn}. Use this only for a mistake.',
      submitLabel: 'Reverse payment',
      fields: const [FieldSpec('reason', 'Reason', required: true, hint: 'e.g. Recorded for the wrong student')],
      onSubmit: (v) async {
        try {
          await FeesRepository.instance.reversePayment(p.id, v['reason']!);
        } catch (e) {
          throw FormError(friendlyError(e));
        }
      },
    );
    if (ok == true) {
      widget.onChanged?.call();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final f = widget.fee;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(f.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${money(f.amount, f.currency)} due  ·  ${money(f.paid, f.currency)} paid  ·  ${money(f.balance > 0 ? f.balance : 0, f.currency)} owed',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 14),
            Text('Payment history', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(_error!, style: TextStyle(color: cs.error))
            else if (_payments.isEmpty)
              const HintBanner(text: 'No payment has been recorded for this fee yet.')
            else
              for (final p in _payments) ...[
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(money(p.amount, f.currency),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              decoration: p.isReversed ? TextDecoration.lineThrough : null,
                            )),
                      ),
                      StatusPill(
                        label: p.isOnline ? 'Verified online payment' : 'Recorded by school',
                        color: p.isOnline ? AppTheme.green : AppTheme.gold,
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('${p.paidOn}  ·  ${p.methodLabel}${(p.reference ?? '').isEmpty ? '' : '  ·  Ref ${p.reference}'}',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    if ((p.note ?? '').isNotEmpty) Text(p.note!, style: theme.textTheme.bodySmall),
                    if (p.isReversed)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Reversed: ${p.reversalReason}',
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
                      ),
                    if (widget.admin && !p.isReversed && !p.isOnline)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(onPressed: () => _reverse(p), child: const Text('Reverse')),
                      ),
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
