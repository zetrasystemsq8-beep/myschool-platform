import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'models.dart';
import 'school_repository.dart';

class SchoolRow {
  const SchoolRow({
    required this.id,
    required this.code,
    required this.name,
    required this.isActive,
    required this.isListed,
    this.city,
    this.state,
  });

  final String id;
  final String code;
  final String name;
  final bool isActive;
  final bool isListed;
  final String? city;
  final String? state;

  factory SchoolRow.fromMap(Map<String, dynamic> m) => SchoolRow(
        id: m['id'] as String,
        code: m['school_code'] as String,
        name: m['name'] as String,
        isActive: (m['is_active'] as bool?) ?? true,
        isListed: (m['is_listed'] as bool?) ?? true,
        city: m['city'] as String?,
        state: m['state'] as String?,
      );
}

class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    required this.isCurrent,
    required this.terms,
  });

  final String id;
  final String name;
  final String start;
  final String end;
  final bool isCurrent;
  final List<TermInfo> terms;
}

class ClassRow {
  const ClassRow({required this.id, required this.name, this.level});
  final String id;
  final String name;
  final String? level;
}

class SubjectRow {
  const SubjectRow({required this.id, required this.name, required this.code});
  final String id;
  final String name;
  final String code;
}

class StudentRow {
  const StudentRow({
    required this.id,
    required this.admissionNumber,
    required this.firstName,
    required this.lastName,
    required this.status,
    this.userId,
  });

  final String id;
  final String admissionNumber;
  final String firstName;
  final String lastName;
  final String status;
  final String? userId;

  String get name => '$firstName $lastName'.trim();
}

class MemberRow {
  const MemberRow({required this.userId, required this.name, required this.status, this.staffNumber});
  final String userId;
  final String name;
  final String status;
  final String? staffNumber;
}

/// Message for failures of the account-provisioning Edge Function.
String provisionError(Object e) {
  if (e is FunctionException) {
    if (e.status == 404) {
      return 'The account service is not deployed yet. Ask the developer to deploy "myschool-provision-user".';
    }
    final d = e.details;
    if (d is Map && d['error'] is Map) {
      return ((d['error'] as Map)['message'] ?? 'Could not create the account.').toString();
    }
    return 'Could not complete the request. Please try again.';
  }
  return friendlyError(e);
}

/// Platform-admin and school-admin setup calls. Row Level Security and the database
/// functions enforce who may do what; this class only builds the requests.
class SetupRepository {
  SetupRepository._();
  static final instance = SetupRepository._();

  SupabaseClient get _client => Supabase.instance.client;
  late final _db = _client.schema(AppConfig.schema);

  // ------------------------------------------------------------ platform admin

  Future<bool> isPlatformAdmin(String uid) async {
    final row = await _db.from('profiles').select('is_platform_admin').eq('id', uid).maybeSingle();
    return row?['is_platform_admin'] == true;
  }

  Future<List<SchoolRow>> allSchools() async {
    final rows = await _db
        .from('schools')
        .select('id, school_code, name, city, state, is_active, is_listed')
        .order('name');
    return rows.map(SchoolRow.fromMap).toList();
  }

  Future<void> createSchool({
    required String code,
    required String name,
    String? motto,
    String? city,
    String? state,
  }) async {
    await _db.rpc('create_school', params: {
      'p_school_code': code,
      'p_name': name,
      'p_motto': motto,
      'p_city': city,
      'p_state': state,
    });
  }

  Future<void> setSchoolStatus(String id, {required bool active, required bool listed}) async {
    await _db.rpc('set_school_status', params: {
      'p_school_id': id,
      'p_active': active,
      'p_listed': listed,
    });
  }

  /// Creates accounts / resets passwords through the Edge Function (needs the service role).
  Future<Map<String, dynamic>> provision(Map<String, dynamic> body) async {
    final res = await _client.functions.invoke('myschool-provision-user', body: body);
    final d = res.data;
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  // ------------------------------------------------------------ sessions and terms

  Future<List<SessionInfo>> sessions(String schoolId) async {
    final sessionRows = await _db
        .from('academic_sessions')
        .select('id, name, start_date, end_date, is_current')
        .eq('school_id', schoolId)
        .order('start_date', ascending: false);
    final termRows = await _db
        .from('terms')
        .select('id, session_id, name, term_number, is_current')
        .eq('school_id', schoolId)
        .order('term_number');
    return [
      for (final s in sessionRows)
        SessionInfo(
          id: s['id'] as String,
          name: s['name'] as String,
          start: s['start_date'] as String,
          end: s['end_date'] as String,
          isCurrent: (s['is_current'] as bool?) ?? false,
          terms: [
            for (final t in termRows)
              if (t['session_id'] == s['id']) TermInfo.fromMap(t),
          ],
        ),
    ];
  }

  Future<String?> currentSessionId(String schoolId) async {
    final row = await _db
        .from('academic_sessions')
        .select('id')
        .eq('school_id', schoolId)
        .eq('is_current', true)
        .maybeSingle();
    return row?['id'] as String?;
  }

  Future<void> addSession(String schoolId, String name, String start, String end, bool current) async {
    if (current) {
      await _db.from('academic_sessions').update({'is_current': false}).eq('school_id', schoolId);
    }
    await _db.from('academic_sessions').insert({
      'school_id': schoolId,
      'name': name,
      'start_date': start,
      'end_date': end,
      'is_current': current,
    });
  }

  Future<void> setCurrentSession(String schoolId, String id) async {
    await _db.from('academic_sessions').update({'is_current': false}).eq('school_id', schoolId);
    await _db.from('academic_sessions').update({'is_current': true}).eq('id', id);
  }

  Future<void> addTerm(String schoolId, String sessionId, int number, String name) async {
    await _db.from('terms').insert({
      'school_id': schoolId,
      'session_id': sessionId,
      'term_number': number,
      'name': name,
    });
  }

  Future<void> setCurrentTerm(String schoolId, String id) async {
    await _db.from('terms').update({'is_current': false}).eq('school_id', schoolId);
    await _db.from('terms').update({'is_current': true}).eq('id', id);
  }

  // ------------------------------------------------------------ classes and subjects

  Future<List<ClassRow>> classes(String schoolId) async {
    final rows = await _db.from('classes').select('id, name, level').eq('school_id', schoolId).order('name');
    return [for (final r in rows) ClassRow(id: r['id'] as String, name: r['name'] as String, level: r['level'] as String?)];
  }

  Future<void> addClass(String schoolId, String name, String? level) async {
    await _db.from('classes').insert({'school_id': schoolId, 'name': name, 'level': level});
  }

  Future<List<SubjectRow>> subjects(String schoolId) async {
    final rows = await _db.from('subjects').select('id, name, code').eq('school_id', schoolId).order('name');
    return [for (final r in rows) SubjectRow(id: r['id'] as String, name: r['name'] as String, code: r['code'] as String)];
  }

  Future<void> addSubject(String schoolId, String name, String code) async {
    await _db.from('subjects').insert({'school_id': schoolId, 'name': name, 'code': code});
  }

  // ------------------------------------------------------------ people

  Future<List<StudentRow>> students(String schoolId) async {
    final rows = await _db
        .from('students')
        .select('id, user_id, admission_number, first_name, last_name, status')
        .eq('school_id', schoolId)
        .order('last_name');
    return [
      for (final r in rows)
        StudentRow(
          id: r['id'] as String,
          userId: r['user_id'] as String?,
          admissionNumber: r['admission_number'] as String,
          firstName: r['first_name'] as String,
          lastName: r['last_name'] as String,
          status: r['status'] as String,
        ),
    ];
  }

  Future<List<MemberRow>> members(String schoolId, String role) async {
    final rows = await _db
        .from('school_members')
        .select('user_id, status, staff_number, profiles(full_name)')
        .eq('school_id', schoolId)
        .eq('role', role);
    final list = [
      for (final r in rows)
        MemberRow(
          userId: r['user_id'] as String,
          status: r['status'] as String,
          staffNumber: r['staff_number'] as String?,
          name: ((r['profiles'] as Map?)?['full_name'] as String?)?.trim().isNotEmpty == true
              ? (r['profiles'] as Map)['full_name'] as String
              : 'Unnamed',
        ),
    ];
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<void> enroll(String schoolId, String studentId, String classId, String sessionId) async {
    await _db.from('enrollments').insert({
      'school_id': schoolId,
      'student_id': studentId,
      'class_id': classId,
      'session_id': sessionId,
    });
  }

  Future<void> addAssignment(
      String schoolId, String teacherUid, String classId, String subjectId, String sessionId) async {
    await _db.from('teaching_assignments').insert({
      'school_id': schoolId,
      'teacher_user_id': teacherUid,
      'class_id': classId,
      'subject_id': subjectId,
      'session_id': sessionId,
    });
  }

  Future<void> deleteAssignment(String id) async {
    await _db.from('teaching_assignments').delete().eq('id', id);
  }
}
