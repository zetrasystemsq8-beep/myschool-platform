import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'models.dart';

/// Fees. The school RECORDS payments; the app never claims money was received online.
/// All writes go through admin-only, audited database functions.
class FeesRepository {
  FeesRepository._();
  static final instance = FeesRepository._();

  late final _db = Supabase.instance.client.schema(AppConfig.schema);

  Future<List<FeeBalance>> forStudent(String studentId) async {
    final rows = await _db
        .from('student_fee_balances')
        .select()
        .eq('student_id', studentId)
        .order('due_date', ascending: true);
    return rows.map(FeeBalance.fromMap).toList();
  }

  Future<List<FeeBalance>> forSchool(String schoolId) async {
    final rows = await _db.from('student_fee_balances').select().eq('school_id', schoolId).limit(1000);
    return rows.map(FeeBalance.fromMap).toList();
  }

  Future<List<FeePayment>> payments(String studentFeeId) async {
    final rows = await _db
        .from('fee_payments')
        .select('id, amount, paid_on, method, source, reference, note, reversed_at, reversal_reason')
        .eq('student_fee_id', studentFeeId)
        .order('paid_on', ascending: false);
    return rows.map(FeePayment.fromMap).toList();
  }

  Future<List<FeeCategory>> categories(String schoolId) async {
    final rows = await _db
        .from('fee_categories')
        .select('id, name, description, is_active')
        .eq('school_id', schoolId)
        .order('name');
    return rows.map(FeeCategory.fromMap).toList();
  }

  Future<void> addCategory(String schoolId, String name, String? description) async {
    await _db.from('fee_categories').insert({'school_id': schoolId, 'name': name, 'description': description});
  }

  Future<void> setCategoryActive(String id, bool active) async {
    await _db.from('fee_categories').update({'is_active': active}).eq('id', id);
  }

  Future<List<FeeChargeRow>> charges(String schoolId) async {
    final rows = await _db
        .from('fee_charges')
        .select(
            'id, title, amount, currency, due_date, fee_categories(name), classes(name), students(first_name, last_name), academic_sessions(name), terms(name)')
        .eq('school_id', schoolId)
        .order('created_at', ascending: false);
    return rows.map(FeeChargeRow.fromMap).toList();
  }

  /// Returns how many students the fee was assigned to.
  Future<int> createCharge({
    required String categoryId,
    required String title,
    required double amount,
    required String sessionId,
    String? termId,
    String? classId,
    String? studentId,
    String? dueDate,
  }) async {
    final n = await _db.rpc('create_fee_charge', params: {
      'p_category': categoryId,
      'p_title': title,
      'p_amount': amount,
      'p_due': dueDate,
      'p_session': sessionId,
      'p_term': termId,
      'p_class': classId,
      'p_student': studentId,
    });
    return (n as num?)?.toInt() ?? 0;
  }

  Future<int> sync(String chargeId) async {
    final n = await _db.rpc('sync_fee_charge', params: {'p_charge': chargeId});
    return (n as num?)?.toInt() ?? 0;
  }

  Future<void> recordPayment({
    required String studentFeeId,
    required double amount,
    required String paidOn,
    required String method,
    String? reference,
    String? note,
  }) async {
    await _db.rpc('record_fee_payment', params: {
      'p_student_fee': studentFeeId,
      'p_amount': amount,
      'p_paid_on': paidOn,
      'p_method': method,
      'p_reference': reference,
      'p_note': note,
    });
  }

  Future<void> reversePayment(String paymentId, String reason) async {
    await _db.rpc('reverse_fee_payment', params: {'p_payment': paymentId, 'p_reason': reason});
  }
}
