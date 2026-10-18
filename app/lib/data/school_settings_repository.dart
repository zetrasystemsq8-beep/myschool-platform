import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'models.dart';

/// The school's own profile, scoring and grading. The database allows only that school's
/// administrator to change these, and never lets anyone change the School ID.
class SchoolSettingsRepository {
  SchoolSettingsRepository._();
  static final instance = SchoolSettingsRepository._();

  SupabaseClient get _client => Supabase.instance.client;
  late final _db = Supabase.instance.client.schema(AppConfig.schema);

  Future<Map<String, dynamic>> loadProfile(String schoolId) async {
    return await _db
        .from('schools')
        .select('school_code, name, motto, description, website, contact_email, contact_phone, address, city, state, country, logo_path')
        .eq('id', schoolId)
        .single();
  }

  Future<void> saveProfile(String schoolId, Map<String, dynamic> values) async {
    await _db.from('schools').update(values).eq('id', schoolId);
  }

  Future<({double ca, double exam, bool separateApprover})> loadScoring(String schoolId) async {
    final row = await _db
        .from('school_settings')
        .select('ca_max, exam_max, require_separate_approver')
        .eq('school_id', schoolId)
        .single();
    return (
      ca: (row['ca_max'] as num).toDouble(),
      exam: (row['exam_max'] as num).toDouble(),
      separateApprover: (row['require_separate_approver'] as bool?) ?? false,
    );
  }

  /// Test + exam maximum must add up to 100 (enforced by the database too).
  Future<void> saveScoring(String schoolId, double ca, double exam) async {
    await _db.from('school_settings').update({'ca_max': ca, 'exam_max': exam}).eq('school_id', schoolId);
  }

  Future<void> setSeparateApprover(String schoolId, bool value) async {
    await _db.from('school_settings').update({'require_separate_approver': value}).eq('school_id', schoolId);
  }

  // ---- grading scale

  Future<void> addBand(String schoolId, String grade, double minScore, String? remark) async {
    await _db.from('grading_scales').insert({
      'school_id': schoolId,
      'grade': grade,
      'min_score': minScore,
      'remark': remark,
    });
  }

  Future<void> updateBand(String schoolId, String oldGrade, String grade, double minScore, String? remark) async {
    await _db
        .from('grading_scales')
        .update({'grade': grade, 'min_score': minScore, 'remark': remark})
        .eq('school_id', schoolId)
        .eq('grade', oldGrade);
  }

  Future<void> deleteBand(String schoolId, String grade) async {
    await _db.from('grading_scales').delete().eq('school_id', schoolId).eq('grade', grade);
  }

  // ---- logo

  String _mime(String ext) => switch (ext.toLowerCase()) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };

  /// Uploads to {school_id}/logo-<time>.<ext> (the bucket policy allows only this school's admin),
  /// points the school at it, and removes the previous file.
  Future<String> uploadLogo(String schoolId, Uint8List bytes, String ext, String? oldPath) async {
    final safeExt = ['png', 'webp'].contains(ext.toLowerCase()) ? ext.toLowerCase() : 'jpg';
    final path = '$schoolId/logo-${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    final bucket = _client.storage.from(AppConfig.logoBucket);
    await bucket.uploadBinary(path, bytes, fileOptions: FileOptions(contentType: _mime(safeExt), upsert: true));
    await _db.from('schools').update({'logo_path': path}).eq('id', schoolId);
    if (oldPath != null && oldPath != path && oldPath.startsWith('$schoolId/')) {
      try {
        await bucket.remove([oldPath]);
      } catch (_) {
        // The old file is just left behind; nothing depends on it.
      }
    }
    return path;
  }
}
