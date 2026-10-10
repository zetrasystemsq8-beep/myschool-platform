import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'models.dart';
import 'school_repository.dart';

class AuthRepository {
  AuthRepository._();
  static final instance = AuthRepository._();

  SupabaseClient get _client => Supabase.instance.client;
  PostgrestClient get _db => _client.schema(AppConfig.schema);

  bool get hasSession => _client.auth.currentSession != null;
  String? get userId => _client.auth.currentUser?.id;
  String? get email => _client.auth.currentUser?.email;

  /// Parents, teachers and admins.
  Future<void> signInWithEmail(String email, String password) async {
    await _client.auth
        .signInWithPassword(email: email.trim(), password: password);
  }

  /// Students: School ID + admission number + PIN, checked by an Edge Function
  /// that returns a normal Supabase session.
  Future<void> signInStudent({
    required String schoolCode,
    required String admissionNumber,
    required String pin,
  }) async {
    final res = await _client.functions.invoke('myschool-student-login', body: {
      'school_code': schoolCode,
      'admission_number': admissionNumber,
      'pin': pin,
    });
    final data = res.data;
    final session = (data is Map) ? data['session'] : null;
    final refresh = (session is Map) ? session['refresh_token'] as String? : null;
    if (refresh == null) throw Exception('Sign-in failed.');
    await _client.auth.setSession(refresh);
  }

  /// The signed-in user's role in [schoolId], or null if they do not belong there.
  Future<Member?> membershipFor(String schoolId) async {
    final uid = userId;
    if (uid == null) return null;
    final rows = await _db
        .from('school_members')
        .select('school_id, role, status')
        .eq('user_id', uid)
        .eq('school_id', schoolId)
        .limit(1);
    if (rows.isEmpty) return null;
    return Member.fromMap(rows.first);
  }

  Future<void> signOut() => _client.auth.signOut();
}

/// Human-friendly message for any sign-in failure.
String authError(Object e) {
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return 'Email or password is incorrect.';
    }
    return e.message;
  }
  if (e is FunctionException) {
    if (e.status == 404) {
      return 'Student sign-in is not available yet. Please ask your school.';
    }
    final d = e.details;
    if (d is Map && d['error'] is Map) {
      return ((d['error'] as Map)['message'] ?? 'Sign-in failed.').toString();
    }
    return 'Sign-in failed. Please try again.';
  }
  return friendlyError(e);
}
