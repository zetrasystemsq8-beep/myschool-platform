import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'models.dart';

/// Attendance. Reading is limited by the database (teachers: their classes; parents: their children).
/// Writing happens only through the audited mark_attendance function.
class AttendanceRepository {
  AttendanceRepository._();
  static final instance = AttendanceRepository._();

  late final _db = Supabase.instance.client.schema(AppConfig.schema);

  Future<List<AttendanceRecord>> forClassDay(String classId, DateTime day) async {
    final rows = await _db
        .from('attendance_records')
        .select('student_id, attendance_date, status, note')
        .eq('class_id', classId)
        .eq('attendance_date', isoDate(day));
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  Future<List<AttendanceRecord>> forClassRange(String classId, DateTime from, DateTime to) async {
    final rows = await _db
        .from('attendance_records')
        .select('student_id, attendance_date, status, note')
        .eq('class_id', classId)
        .gte('attendance_date', isoDate(from))
        .lte('attendance_date', isoDate(to));
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  Future<List<AttendanceRecord>> forStudentRange(String studentId, DateTime from, DateTime to) async {
    final rows = await _db
        .from('attendance_records')
        .select('student_id, attendance_date, status, note')
        .eq('student_id', studentId)
        .gte('attendance_date', isoDate(from))
        .lte('attendance_date', isoDate(to))
        .order('attendance_date', ascending: false);
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  /// entries: [{student_id, status}] where status is present | late | absent.
  Future<void> mark(String classId, DateTime day, List<Map<String, String>> entries) async {
    await _db.rpc('mark_attendance', params: {
      'p_class_id': classId,
      'p_date': isoDate(day),
      'p_entries': entries,
    });
  }
}
