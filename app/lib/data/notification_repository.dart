import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'models.dart';

/// In-app notifications. The database creates them (when an announcement is published);
/// a user can only ever read their own and mark them read.
class NotificationRepository {
  NotificationRepository._();
  static final instance = NotificationRepository._();

  late final _db = Supabase.instance.client.schema(AppConfig.schema);

  Future<List<NotificationItem>> list(String schoolId) async {
    final rows = await _db
        .from('notifications')
        .select('id, kind, title, body, entity_id, created_at, read_at')
        .eq('school_id', schoolId)
        .order('created_at', ascending: false)
        .limit(60);
    return rows.map(NotificationItem.fromMap).toList();
  }

  Future<int> unreadCount(String schoolId) async {
    final rows = await _db
        .from('notifications')
        .select('id')
        .eq('school_id', schoolId)
        .filter('read_at', 'is', null);
    return rows.length;
  }

  Future<void> markRead(String id) async {
    await _db.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
  }

  Future<void> markAllRead(String schoolId) async {
    await _db
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('school_id', schoolId)
        .filter('read_at', 'is', null);
  }
}
