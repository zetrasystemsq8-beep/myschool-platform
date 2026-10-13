import 'package:flutter/material.dart';

import '../data/fees_repository.dart';
import '../data/models.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../data/setup_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/async_list.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';
import '../widgets/help.dart';
import 'student_fees_admin_screen.dart';

class _Owing {
  _Owing(this.studentId, this.name, this.admission);

  final String studentId;
  final String name;
  final String admission;
  double due = 0, paid = 0, balance = 0;
  int fees = 0;
  String currency = 'NGN';
}

/// Administrator's fees area: who owes what, the fees that were set, and the fee types.
class AdminFeesScreen extends StatelessWidget {
  const AdminFeesScreen({super.key, required this.school});

  final School school;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        const TabBar(tabs: [Tab(text: 'Who owes'), Tab(text: 'Fees'), Tab(text: 'Fee types')]),
        Expanded(
          child: TabBarView(children: [
            _BalancesTab(school: school),
            _ChargesTab(school: school),
            _TypesTab(school: school),
          ]),
        ),
      ]),
    );
  }
}

class _BalancesTab extends StatelessWidget {
  const _BalancesTab({required this.school});

  final School school;

  Future<List<_Owing>> _load() async {
    final rows = await FeesRepository.instance.forSchool(school.id);
    final byStudent = <String, _Owing>{};
    for (final f in rows) {
      final o = byStudent.putIfAbsent(f.studentId, () => _Owing(f.studentId, f.studentName, f.admissionNumber));
      o.due += f.amount;
      o.paid += f.paid;
      o.balance += f.balance > 0 ? f.balance : 0;
      o.fees++;
      o.currency = f.currency;
    }
    final list = byStudent.values.toList()..sort((a, b) => b.balance.compareTo(a.balance));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AsyncList<_Owing>(
      load: _load,
      emptyIcon: Icons.receipt_long_outlined,
      emptyTitle: 'No fees yet',
      emptyMessage: 'Create a fee under the "Fees" tab. Students then appear here with what they owe.',
      itemBuilder: (ctx, o, reload) => AppCard(
        onTap: () async {
          await Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => StudentFeesAdminScreen(studentId: o.studentId, studentName: o.name),
          ));
          await reload();
        },
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text('${o.admission}  ·  ${o.fees} fee${o.fees == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(o.balance > 0 ? money(o.balance, o.currency) : 'Cleared',
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: o.balance > 0 ? const Color(0xFFC62828) : AppTheme.green)),
            Text(o.balance > 0 ? 'owed' : '',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ]),
      ),
    );
  }
}

class _ChargesTab extends StatelessWidget {
  const _ChargesTab({required this.school});

  final School school;

  Future<bool?> _new(BuildContext context) async {
    try {
      final repo = FeesRepository.instance;
      final setup = SetupRepository.instance;
      final categories = (await repo.categories(school.id)).where((c) => c.isActive).toList();
      final sessions = await setup.sessions(school.id);
      final classes = await setup.classes(school.id);
      final students = await setup.students(school.id);
      if (!context.mounted) return false;
      if (categories.isEmpty) {
        notify(context, 'Add a fee type first (the "Fee types" tab), for example Tuition.', error: true);
        return false;
      }
      final current = sessions.where((s) => s.isCurrent).map((s) => s.id).firstOrNull ?? '';
      var created = 0;
      final ok = await showFormSheet(
        context,
        title: 'New fee',
        subtitle: 'Choose a class (every student in it) OR one student.',
        submitLabel: 'Create fee',
        fields: [
          FieldSpec('category', 'Fee type', kind: FieldKind.choice, required: true,
              options: [for (final c in categories) (c.id, c.name)]),
          const FieldSpec('title', 'Name of the fee', required: true, hint: 'First term tuition'),
          const FieldSpec('amount', 'Amount (₦)', required: true, keyboard: TextInputType.numberWithOptions(decimal: true)),
          const FieldSpec('due', 'Due date (optional)', kind: FieldKind.date),
          FieldSpec('session', 'School year', kind: FieldKind.choice, required: true, initial: current,
              options: [for (final s in sessions) (s.id, s.name)]),
          FieldSpec('term', 'Term (optional)', kind: FieldKind.choice, options: [
            for (final s in sessions) for (final t in s.terms) (t.id, '${s.name} · ${t.name}'),
          ]),
          FieldSpec('class', 'For a whole class', kind: FieldKind.choice, options: [for (final c in classes) (c.id, c.name)]),
          FieldSpec('student', 'OR for one student', kind: FieldKind.choice,
              options: [for (final s in students) (s.id, '${s.name} (${s.admissionNumber})')]),
        ],
        onSubmit: (v) async {
          final amount = double.tryParse(v['amount']!.replaceAll(',', ''));
          if (amount == null || amount <= 0) throw FormError('Enter an amount above zero.');
          if (v['class']!.isEmpty == v['student']!.isEmpty) {
            throw FormError('Choose either a class or one student, not both.');
          }
          try {
            created = await repo.createCharge(
              categoryId: v['category']!,
              title: v['title']!,
              amount: amount,
              sessionId: v['session']!,
              termId: v['term']!.isEmpty ? null : v['term'],
              classId: v['class']!.isEmpty ? null : v['class'],
              studentId: v['student']!.isEmpty ? null : v['student'],
              dueDate: v['due']!.isEmpty ? null : v['due'],
            );
          } catch (e) {
            throw FormError(friendlyError(e));
          }
        },
      );
      if (ok == true && context.mounted) notify(context, 'Fee created for $created student${created == 1 ? '' : 's'}.');
      return ok;
    } catch (e) {
      if (context.mounted) notify(context, friendlyError(e), error: true);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AsyncList<FeeChargeRow>(
      load: () => FeesRepository.instance.charges(school.id),
      emptyIcon: Icons.request_quote_outlined,
      emptyTitle: 'No fees set yet',
      emptyMessage: 'Tap "New fee" to set an amount for a class or a student.',
      addLabel: 'New fee',
      onAdd: () => _new(context),
      itemBuilder: (ctx, c, reload) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(c.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
            PopupMenuButton<String>(
              onSelected: (_) async {
                try {
                  final n = await FeesRepository.instance.sync(c.id);
                  if (ctx.mounted) {
                    notify(ctx, n == 0 ? 'Nobody was missing this fee.' : 'Added to $n new student${n == 1 ? '' : 's'}.');
                  }
                } catch (e) {
                  if (ctx.mounted) notify(ctx, friendlyError(e), error: true);
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'sync', child: Text('Add to students who joined later'))],
            ),
          ]),
          Text('${c.categoryName}  ·  ${c.scope}',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          Text('${c.sessionName}${(c.termName ?? '').isEmpty ? '' : '  ·  ${c.termName}'}${c.dueDate == null ? '' : '  ·  due ${c.dueDate}'}',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(money(c.amount, c.currency), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

class _TypesTab extends StatelessWidget {
  const _TypesTab({required this.school});

  final School school;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AsyncList<FeeCategory>(
      load: () => FeesRepository.instance.categories(school.id),
      emptyIcon: Icons.category_outlined,
      emptyTitle: 'No fee types yet',
      emptyMessage: 'Add types such as Tuition, Uniform or Books. You choose one whenever you create a fee.',
      addLabel: 'New fee type',
      onAdd: () => showFormSheet(
        context,
        title: 'New fee type',
        submitLabel: 'Save',
        fields: const [
          FieldSpec('name', 'Name', required: true, hint: 'Tuition'),
          FieldSpec('desc', 'Description (optional)'),
        ],
        onSubmit: (v) async {
          try {
            await FeesRepository.instance.addCategory(school.id, v['name']!, v['desc']!.isEmpty ? null : v['desc']);
          } catch (e) {
            throw FormError(friendlyError(e));
          }
        },
      ),
      itemBuilder: (ctx, c, reload) => AppCard(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              if ((c.description ?? '').isNotEmpty)
                Text(c.description!, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          Switch(
            value: c.isActive,
            onChanged: (v) async {
              try {
                await FeesRepository.instance.setCategoryActive(c.id, v);
                await reload();
              } catch (e) {
                if (ctx.mounted) notify(ctx, friendlyError(e), error: true);
              }
            },
          ),
        ]),
      ),
    );
  }
}

const adminFeesHelp = HelpButton(
  title: 'Fees',
  intro: 'You record the money the school receives. Nothing is paid or checked online.',
  steps: [
    'Fee types: add types like Tuition or Uniform (once).',
    'Fees: tap "New fee", choose the type, amount and a class or one student.',
    'Who owes: tap a student, then "Record payment" when money is received at the office.',
    'Parents see their child\'s fees, payments and balance. Teachers cannot see fees.',
  ],
);
