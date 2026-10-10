import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'models.dart';

/// Teacher reads/writes. The database decides what a teacher may touch: only sheets of
/// classes+subjects assigned to them, only while the sheet is a draft.
class TeacherRepository {
  TeacherRepository._();
  static final instance = TeacherRepository._();

  PostgrestClient get _db => Supabase.instance.client.schema(AppConfig.schema);

  Future<List<Assignment>> assignments(String uid, String schoolId) async {
    final rows = await _db
        .from('teaching_assignments')
        .select(
            'id, class_id, subject_id, session_id, classes(name), subjects(name, code), academic_sessions(name)')
        .eq('teacher_user_id', uid)
        .eq('school_id', schoolId);
    final list = rows.map(Assignment.fromMap).toList();
    list.sort((a, b) {
      final bySession = b.sessionName.compareTo(a.sessionName);
      if (bySession != 0) return bySession;
      final byClass = a.className.compareTo(b.className);
      return byClass != 0 ? byClass : a.subjectName.compareTo(b.subjectName);
    });
    return list;
  }

  Future<List<TermInfo>> terms(String schoolId, String sessionId) async {
    final rows = await _db
        .from('terms')
        .select('id, name, term_number, is_current')
        .eq('school_id', schoolId)
        .eq('session_id', sessionId)
        .order('term_number');
    return rows.map(TermInfo.fromMap).toList();
  }

  Future<Limits> limits(String schoolId) async {
    final row = await _db
        .from('school_settings')
        .select('ca_max, exam_max')
        .eq('school_id', schoolId)
        .single();
    return Limits((row['ca_max'] as num).toDouble(), (row['exam_max'] as num).toDouble());
  }

  Future<List<RosterEntry>> roster(String classId, String sessionId) async {
    final rows = await _db
        .from('enrollments')
        .select('student_id, students(admission_number, first_name, last_name)')
        .eq('class_id', classId)
        .eq('session_id', sessionId)
        .neq('status', 'withdrawn');
    final list = rows.map(RosterEntry.fromMap).whereType<RosterEntry>().toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<SheetInfo?> findSheet(String termId, String classId, String subjectId) async {
    final row = await _db
        .from('result_sheets')
        .select('id, status, return_note')
        .eq('term_id', termId)
        .eq('class_id', classId)
        .eq('subject_id', subjectId)
        .maybeSingle();
    return row == null ? null : SheetInfo.fromMap(row);
  }

  /// Creates the draft sheet the first time a teacher saves scores.
  Future<SheetInfo> createSheet(String schoolId, String uid, String termId, String classId, String subjectId) async {
    try {
      final row = await _db
          .from('result_sheets')
          .insert({
            'school_id': schoolId,
            'term_id': termId,
            'class_id': classId,
            'subject_id': subjectId,
            'status': 'draft',
            'created_by': uid,
          })
          .select('id, status, return_note')
          .single();
      return SheetInfo.fromMap(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final existing = await findSheet(termId, classId, subjectId);
        if (existing != null) return existing;
      }
      rethrow;
    }
  }

  Future<List<ScoreItem>> items(String sheetId) async {
    final rows = await _db
        .from('result_items')
        .select('student_id, ca_score, exam_score, total, grade')
        .eq('sheet_id', sheetId);
    return rows.map(ScoreItem.fromMap).toList();
  }

  Future<void> saveItems(List<Map<String, dynamic>> rows) async {
    await _db.from('result_items').upsert(rows, onConflict: 'sheet_id,student_id');
  }

  Future<void> submit(String sheetId) async {
    await _db.rpc('submit_result_sheet', params: {'p_sheet_id': sheetId});
  }
}
