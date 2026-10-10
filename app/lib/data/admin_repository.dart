import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'models.dart';

/// Administrator actions. Every call is re-checked by the database: only an active admin
/// of the school can approve/publish sheets or manage announcements.
class AdminRepository {
  AdminRepository._();
  static final instance = AdminRepository._();

  PostgrestClient get _db => Supabase.instance.client.schema(AppConfig.schema);

  static const _sheetCols =
      'id, status, return_note, classes(name), subjects(name, code), terms(name, term_number, academic_sessions(name))';

  Future<List<SheetSummary>> sheets(String schoolId, String status) async {
    final rows = await _db
        .from('result_sheets')
        .select(_sheetCols)
        .eq('school_id', schoolId)
        .eq('status', status)
        .order('updated_at', ascending: false);
    return rows.map(SheetSummary.fromMap).toList();
  }

  Future<SheetSummary?> sheet(String id) async {
    final row = await _db.from('result_sheets').select(_sheetCols).eq('id', id).maybeSingle();
    return row == null ? null : SheetSummary.fromMap(row);
  }

  Future<List<ReviewItem>> items(String sheetId) async {
    final rows = await _db
        .from('result_items')
        .select('ca_score, exam_score, total, grade, students(admission_number, first_name, last_name)')
        .eq('sheet_id', sheetId);
    final list = rows.map(ReviewItem.fromMap).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<void> approve(String sheetId) =>
      _db.rpc('approve_result_sheet', params: {'p_sheet_id': sheetId});

  Future<void> publish(String sheetId) =>
      _db.rpc('publish_result_sheet', params: {'p_sheet_id': sheetId});

  Future<void> returnToTeacher(String sheetId, String note) =>
      _db.rpc('return_result_sheet', params: {'p_sheet_id': sheetId, 'p_note': note});

  Future<void> unpublish(String sheetId, String reason) =>
      _db.rpc('unpublish_result_sheet', params: {'p_sheet_id': sheetId, 'p_reason': reason});

  // ---- announcements (admins also see drafts and archived ones)

  Future<List<Announcement>> announcements(String schoolId) async {
    final rows = await _db
        .from('announcements')
        .select('id, title, body, audience, status, published_at')
        .eq('school_id', schoolId)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(Announcement.fromMap).toList();
  }

  /// Insert when [id] is null, otherwise update. author_id / published_at are set by the database.
  Future<void> saveAnnouncement({
    String? id,
    required String schoolId,
    required String title,
    required String body,
    required String audience,
    required String status,
  }) async {
    if (id == null) {
      await _db.from('announcements').insert({
        'school_id': schoolId,
        'title': title,
        'body': body,
        'audience': audience,
        'status': status,
      });
    } else {
      await _db
          .from('announcements')
          .update({'title': title, 'body': body, 'audience': audience, 'status': status})
          .eq('id', id);
    }
  }

  Future<void> deleteAnnouncement(String id) async {
    await _db.from('announcements').delete().eq('id', id);
  }
}
