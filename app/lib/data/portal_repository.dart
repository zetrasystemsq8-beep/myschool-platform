import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'models.dart';

/// Reads for the student/parent portal. Row Level Security in the database decides what is
/// returned, so these queries can only ever see the signed-in user's own data.
class PortalRepository {
  PortalRepository._();
  static final instance = PortalRepository._();

  PostgrestClient get _db => Supabase.instance.client.schema(AppConfig.schema);

  Future<StudentInfo?> myStudentRecord(String uid, String schoolId) async {
    final row = await _db
        .from('students')
        .select('id, admission_number, first_name, last_name')
        .eq('user_id', uid)
        .eq('school_id', schoolId)
        .maybeSingle();
    return row == null ? null : StudentInfo.fromMap(row);
  }

  Future<List<StudentInfo>> children(String uid, String schoolId) async {
    final rows = await _db
        .from('parent_students')
        .select('students(id, admission_number, first_name, last_name)')
        .eq('parent_user_id', uid)
        .eq('school_id', schoolId);
    return rows
        .map((r) => r['students'])
        .whereType<Map>()
        .map((m) => StudentInfo.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<List<ResultRow>> results(String studentId) async {
    final rows = await _db
        .from('published_results')
        .select()
        .eq('student_id', studentId);
    return rows.map(ResultRow.fromMap).toList();
  }

  Future<List<Announcement>> announcements(String schoolId) async {
    final rows = await _db
        .from('announcements')
        .select('id, title, body, audience, published_at')
        .eq('school_id', schoolId)
        .order('published_at', ascending: false)
        .limit(30);
    return rows.map(Announcement.fromMap).toList();
  }

  /// e.g. "JSS 1 A · 2025/2026" (latest enrollment), or null.
  Future<String?> enrollmentLabel(String studentId) async {
    final rows = await _db
        .from('enrollments')
        .select('classes(name), academic_sessions(name)')
        .eq('student_id', studentId)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    final cls = (rows.first['classes'] as Map?)?['name'];
    final ses = (rows.first['academic_sessions'] as Map?)?['name'];
    final parts = [cls, ses].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<String?> fullName(String uid) async {
    final row = await _db
        .from('profiles')
        .select('full_name')
        .eq('id', uid)
        .maybeSingle();
    return row?['full_name'] as String?;
  }
}
