import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'models.dart';

class MeetingsRepository {
  MeetingsRepository._();
  static final instance = MeetingsRepository._();

  late final _db = Supabase.instance.client.schema(AppConfig.schema);

  /// The database returns only the meetings the user may see.
  Future<List<MeetingItem>> list(String schoolId) async {
    final rows = await _db
        .from('meetings')
        .select('id, title, description, starts_at, ends_at, location, class_id, status, classes(name)')
        .eq('school_id', schoolId)
        .order('starts_at', ascending: true);
    return rows.map(MeetingItem.fromMap).toList();
  }

  /// A parent's own answers: meeting id -> attending | not_attending.
  Future<Map<String, String>> myResponses() async {
    final rows = await _db.from('meeting_rsvps').select('meeting_id, response');
    return {for (final r in rows) r['meeting_id'] as String: r['response'] as String};
  }

  Future<void> respond(String meetingId, String response) async {
    await _db.rpc('respond_to_meeting', params: {'p_meeting': meetingId, 'p_response': response, 'p_note': null});
  }

  Future<void> save({
    String? id,
    required String schoolId,
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
    String? location,
    String? classId,
  }) async {
    final data = {
      'title': title,
      'description': description,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'location': location,
      'class_id': classId,
    };
    if (id == null) {
      await _db.from('meetings').insert({'school_id': schoolId, ...data});
    } else {
      await _db.from('meetings').update(data).eq('id', id);
    }
  }

  Future<void> cancel(String id) async {
    await _db.from('meetings').update({'status': 'cancelled'}).eq('id', id);
  }

  Future<List<RsvpRow>> rsvpReport(String meetingId) async {
    final rows = await _db.rpc('meeting_rsvp_report', params: {'p_meeting': meetingId});
    return [for (final r in rows as List) RsvpRow.fromMap(Map<String, dynamic>.from(r as Map))];
  }
}
