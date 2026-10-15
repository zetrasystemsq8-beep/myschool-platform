import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'models.dart';

/// Private parent-teacher messages. Everything that changes data goes through database functions
/// that check who may talk to whom; the app cannot write messages directly.
class MessagingRepository {
  MessagingRepository._();
  static final instance = MessagingRepository._();

  late final _db = Supabase.instance.client.schema(AppConfig.schema);

  Future<List<ThreadSummary>> threads(String schoolId) async {
    final rows = await _db.rpc('my_message_threads', params: {'p_school': schoolId});
    return [for (final r in rows as List) ThreadSummary.fromMap(Map<String, dynamic>.from(r as Map))];
  }

  Future<List<MessageContact>> contacts(String schoolId) async {
    final rows = await _db.rpc('my_message_contacts', params: {'p_school': schoolId});
    return [for (final r in rows as List) MessageContact.fromMap(Map<String, dynamic>.from(r as Map))];
  }

  Future<List<ChatMessage>> messages(String threadId) async {
    final rows = await _db
        .from('messages')
        .select('id, sender_id, body, created_at')
        .eq('thread_id', threadId)
        .order('created_at', ascending: true);
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<String> start({required String studentId, required String otherUserId, String? subject, required String body}) async {
    final id = await _db.rpc('start_message_thread', params: {
      'p_student': studentId,
      'p_other': otherUserId,
      'p_subject': subject,
      'p_body': body,
    });
    return id as String;
  }

  Future<void> send(String threadId, String body) async {
    await _db.rpc('send_message', params: {'p_thread': threadId, 'p_body': body});
  }

  Future<void> markRead(String threadId) async {
    await _db.rpc('mark_thread_read', params: {'p_thread': threadId});
  }

  Future<void> report(String messageId, String reason) async {
    await _db.rpc('report_message', params: {'p_message': messageId, 'p_reason': reason});
  }

  // ---- moderation (administrators)

  Future<bool> messagingEnabled(String schoolId) async {
    final row = await _db.from('school_settings').select('messaging_enabled').eq('school_id', schoolId).maybeSingle();
    return (row?['messaging_enabled'] as bool?) ?? true;
  }

  Future<void> setMessagingEnabled(String schoolId, bool enabled) async {
    await _db.from('school_settings').update({'messaging_enabled': enabled}).eq('school_id', schoolId);
  }

  Future<List<MessageReportRow>> reports(String schoolId, String status) async {
    final rows = await _db.rpc('list_message_reports', params: {'p_school': schoolId, 'p_status': status});
    return [for (final r in rows as List) MessageReportRow.fromMap(Map<String, dynamic>.from(r as Map))];
  }

  Future<void> resolveReport(String reportId, String? note, bool closeThread) async {
    await _db.rpc('resolve_message_report', params: {
      'p_report': reportId,
      'p_note': note,
      'p_close_thread': closeThread,
    });
  }

  Future<List<BlockedUser>> blocked(String schoolId) async {
    final rows = await _db
        .from('message_blocks')
        .select('user_id, reason, profiles(full_name)')
        .eq('school_id', schoolId);
    return rows.map(BlockedUser.fromMap).toList();
  }

  Future<void> setBlock(String schoolId, String userId, bool blocked, String? reason) async {
    await _db.rpc('set_messaging_block', params: {
      'p_school': schoolId,
      'p_user': userId,
      'p_blocked': blocked,
      'p_reason': reason,
    });
  }
}
