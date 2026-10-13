import 'package:flutter/material.dart';

import '../data/fees_repository.dart';
import '../data/models.dart';
import '../data/school_repository.dart';
import '../widgets/app_card.dart';
import '../widgets/async_list.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';
import '../widgets/help.dart';
import 'fees_screen.dart';

/// One student's fees for the administrator: record money received, see history.
class StudentFeesAdminScreen extends StatelessWidget {
  const StudentFeesAdminScreen({super.key, required this.studentId, required this.studentName});

  final String studentId;
  final String studentName;

  Future<bool?> _record(BuildContext context, FeeBalance f) {
    return showFormSheet(
      context,
      title: 'Record a payment',
      subtitle: '${f.title}  ·  owes ${money(f.balance, f.currency)}',
      submitLabel: 'Record payment',
      fields: [
        FieldSpec('amount', 'Amount received', required: true, initial: f.balance.toStringAsFixed(0),
            keyboard: const TextInputType.numberWithOptions(decimal: true)),
        FieldSpec('date', 'Date received', kind: FieldKind.date, required: true, initial: isoDate(DateTime.now())),
        const FieldSpec('method', 'How was it paid?', kind: FieldKind.choice, required: true, initial: 'cash', options: [
          ('cash', 'Cash'),
          ('bank_transfer', 'Bank transfer'),
          ('pos', 'POS'),
          ('cheque', 'Cheque'),
          ('other', 'Other'),
        ]),
        const FieldSpec('reference', 'Receipt or transfer reference (optional)'),
        const FieldSpec('note', 'Note (optional)'),
      ],
      onSubmit: (v) async {
        final amount = double.tryParse(v['amount']!.replaceAll(',', ''));
        if (amount == null || amount <= 0) throw FormError('Enter an amount above zero.');
        if (amount > f.balance + 0.001) {
          throw FormError('That is more than is still owed (${money(f.balance, f.currency)}).');
        }
        try {
          await FeesRepository.instance.recordPayment(
            studentFeeId: f.studentFeeId,
            amount: amount,
            paidOn: v['date']!,
            method: v['method']!,
            reference: v['reference']!.isEmpty ? null : v['reference'],
            note: v['note']!.isEmpty ? null : v['note'],
          );
        } catch (e) {
          throw FormError(friendlyError(e));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(studentName),
        actions: const [
          HelpButton(
            title: 'Student fees',
            steps: [
              'Each card is one fee this student owes.',
              'When money is received at the school office, tap "Record payment" and enter what was paid.',
              'Tap "History" to see every payment. Use "Reverse" only to fix a mistake.',
              'These are payments the school recorded. They are not checked by any online payment service.',
            ],
          ),
        ],
      ),
      body: AsyncList<FeeBalance>(
        load: () => FeesRepository.instance.forStudent(studentId),
        emptyIcon: Icons.receipt_long_outlined,
        emptyTitle: 'No fees for this student',
        emptyMessage: 'Create a fee for the class or the student under Fees.',
        itemBuilder: (ctx, f, reload) {
          final color = feeStatusColor(f.status);
          return AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(f.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                StatusPill(label: f.statusLabel, color: color),
              ]),
              Text('${f.categoryName}  ·  ${f.sessionName}',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text('${money(f.paid, f.currency)} paid of ${money(f.amount, f.currency)}',
                  style: theme.textTheme.bodyMedium),
              Text(f.balance > 0 ? 'Owes ${money(f.balance, f.currency)}' : 'Cleared',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 8),
              Row(children: [
                if (f.balance > 0)
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                      onPressed: () async {
                        if (await _record(ctx, f) == true) {
                          if (ctx.mounted) notify(ctx, 'Payment recorded.');
                          await reload();
                        }
                      },
                      child: const Text('Record payment'),
                    ),
                  ),
                if (f.balance > 0) const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: () => showPaymentsSheet(ctx, f, admin: true, onChanged: reload),
                    child: const Text('History'),
                  ),
                ),
              ]),
            ]),
          );
        },
      ),
    );
  }
}
