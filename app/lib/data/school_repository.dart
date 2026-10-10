import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'school.dart';

/// All school-discovery calls. Only public RPCs are used here, so no login is needed.
class SchoolRepository {
  SchoolRepository._();
  static final instance = SchoolRepository._();

  static const _savedKey = 'selected_school';

  SupabaseClient get _client => Supabase.instance.client;
  PostgrestClient get _db => _client.schema(AppConfig.schema);

  Future<List<School>> search(String query) async {
    final rows = await _db.rpc('search_schools', params: {
      'q': query,
      'max_results': 20,
    });
    return (rows as List)
        .map((e) => School.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<School?> byCode(String code) async {
    final rows = await _db.rpc('get_public_school', params: {
      'p_school_code': code,
    });
    final list = rows as List;
    if (list.isEmpty) return null;
    return School.fromMap(Map<String, dynamic>.from(list.first as Map));
  }

  String? logoUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    return _client.storage.from(AppConfig.logoBucket).getPublicUrl(path);
  }

  Future<School?> savedSchool() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedKey);
    if (raw == null) return null;
    try {
      return School.fromMap(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSchool(School school) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedKey, jsonEncode(school.toMap()));
  }

  Future<void> clearSavedSchool() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedKey);
  }
}

/// Turns technical errors into something a student can understand.
String friendlyError(Object error) {
  if (error is PostgrestException) {
    final text = '${error.code} ${error.message}'.toLowerCase();
    if (text.contains('pgrst106') ||
        text.contains('invalid schema') ||
        text.contains('schema must be one of')) {
      return 'The MySchool service is not switched on yet (the "myschool" '
          'schema is not exposed in Supabase).';
    }
    if (const ['23514', '55000', '22023', 'P0002'].contains(error.code)) {
      return error.message; // written for humans by the database rules
    }
    if (error.code == '42501') {
      return error.message.contains('approver must differ')
          ? error.message
          : 'You are not allowed to do that.';
    }
    return 'Service error: ${error.message}';
  }
  final text = error.toString().toLowerCase();
  if (text.contains('socketexception') || text.contains('failed host lookup')) {
    return 'No internet connection. Please check your network and try again.';
  }
  return 'Something went wrong. Please try again.';
}
