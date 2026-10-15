/// Plain data classes shared by the portal screens.

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatDate(DateTime? d) =>
    d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.year}';

/// 70 -> "70", 67.5 -> "67.5"
String fmt(double? v) {
  if (v == null) return '-';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

double? _num(Object? v) => (v as num?)?.toDouble();

/// A user's role inside one school.
class Member {
  const Member({required this.schoolId, required this.role, required this.status});

  final String schoolId;
  final String role; // student | parent | teacher | school_admin
  final String status; // active | suspended

  factory Member.fromMap(Map<String, dynamic> m) => Member(
        schoolId: m['school_id'] as String,
        role: m['role'] as String,
        status: m['status'] as String,
      );

  bool get isActive => status == 'active';
  bool get isStudent => role == 'student';
  bool get isParent => role == 'parent';
  bool get isStaff => role == 'teacher' || role == 'school_admin';
  bool get hasStudentView => isStudent || isParent;

  String get roleLabel => switch (role) {
        'student' => 'Student',
        'parent' => 'Parent',
        'teacher' => 'Teacher',
        'school_admin' => 'School admin',
        _ => role,
      };
}

class StudentInfo {
  const StudentInfo({
    required this.id,
    required this.admissionNumber,
    required this.firstName,
    required this.lastName,
  });

  final String id;
  final String admissionNumber;
  final String firstName;
  final String lastName;

  factory StudentInfo.fromMap(Map<String, dynamic> m) => StudentInfo(
        id: m['id'] as String,
        admissionNumber: m['admission_number'] as String,
        firstName: m['first_name'] as String,
        lastName: m['last_name'] as String,
      );

  String get fullName => '$firstName $lastName'.trim();
}

/// One subject line of a published result (a row of the `published_results` view).
class ResultRow {
  const ResultRow({
    required this.termId,
    required this.termNumber,
    required this.termName,
    required this.sessionName,
    required this.className,
    required this.subjectName,
    required this.subjectCode,
    this.ca,
    this.exam,
    this.total,
    this.grade,
    this.remark,
  });

  final String termId;
  final int termNumber;
  final String termName;
  final String sessionName;
  final String className;
  final String subjectName;
  final String subjectCode;
  final double? ca;
  final double? exam;
  final double? total;
  final String? grade;
  final String? remark;

  factory ResultRow.fromMap(Map<String, dynamic> m) => ResultRow(
        termId: m['term_id'] as String,
        termNumber: (m['term_number'] as num).toInt(),
        termName: m['term_name'] as String,
        sessionName: m['session_name'] as String,
        className: m['class_name'] as String,
        subjectName: m['subject_name'] as String,
        subjectCode: m['subject_code'] as String,
        ca: _num(m['ca_score']),
        exam: _num(m['exam_score']),
        total: _num(m['total']),
        grade: m['grade'] as String?,
        remark: m['remark'] as String?,
      );
}

/// All published subjects of one term.
class TermGroup {
  TermGroup({
    required this.termId,
    required this.termNumber,
    required this.termName,
    required this.sessionName,
    required this.className,
    required this.rows,
  });

  final String termId;
  final int termNumber;
  final String termName;
  final String sessionName;
  final String className;
  final List<ResultRow> rows;

  String get label => '$sessionName · $termName';

  double get totalScore =>
      rows.fold<double>(0, (sum, r) => sum + (r.total ?? 0));

  double? get average {
    final scored = rows.where((r) => r.total != null).toList();
    if (scored.isEmpty) return null;
    return totalScore / scored.length;
  }
}

/// Groups rows by term; newest session/term first, subjects A-Z.
List<TermGroup> groupResults(List<ResultRow> rows) {
  final byTerm = <String, TermGroup>{};
  for (final r in rows) {
    byTerm
        .putIfAbsent(
          r.termId,
          () => TermGroup(
            termId: r.termId,
            termNumber: r.termNumber,
            termName: r.termName,
            sessionName: r.sessionName,
            className: r.className,
            rows: [],
          ),
        )
        .rows
        .add(r);
  }
  final groups = byTerm.values.toList();
  for (final g in groups) {
    g.rows.sort((a, b) => a.subjectName.compareTo(b.subjectName));
  }
  groups.sort((a, b) {
    final bySession = b.sessionName.compareTo(a.sessionName);
    return bySession != 0 ? bySession : b.termNumber.compareTo(a.termNumber);
  });
  return groups;
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    this.status = 'published',
    this.publishedAt,
    this.classId,
    this.className,
  });

  final String id;
  final String title;
  final String body;
  final String audience;
  final String status; // draft | published | archived (admins see all)
  final DateTime? publishedAt;
  final String? classId; // null = whole school
  final String? className;

  factory Announcement.fromMap(Map<String, dynamic> m) => Announcement(
        id: m['id'] as String,
        title: m['title'] as String,
        body: m['body'] as String,
        audience: m['audience'] as String,
        status: (m['status'] as String?) ?? 'published',
        publishedAt: DateTime.tryParse((m['published_at'] as String?) ?? '')?.toLocal(),
        classId: m['class_id'] as String?,
        className: (m['classes'] as Map?)?['name'] as String?,
      );
}

// ---------------------------------------------------------------- teacher side

/// "Teacher X teaches subject Y to class Z in session S".
class Assignment {
  const Assignment({
    required this.id,
    required this.classId,
    required this.subjectId,
    required this.sessionId,
    required this.className,
    required this.subjectName,
    required this.subjectCode,
    required this.sessionName,
  });

  final String id;
  final String classId;
  final String subjectId;
  final String sessionId;
  final String className;
  final String subjectName;
  final String subjectCode;
  final String sessionName;

  factory Assignment.fromMap(Map<String, dynamic> m) {
    String pick(String rel, String key) =>
        ((m[rel] as Map?)?[key] as String?) ?? '';
    return Assignment(
      id: m['id'] as String,
      classId: m['class_id'] as String,
      subjectId: m['subject_id'] as String,
      sessionId: m['session_id'] as String,
      className: pick('classes', 'name'),
      subjectName: pick('subjects', 'name'),
      subjectCode: pick('subjects', 'code'),
      sessionName: pick('academic_sessions', 'name'),
    );
  }
}

class TermInfo {
  const TermInfo({required this.id, required this.name, required this.number, required this.isCurrent});

  final String id;
  final String name;
  final int number;
  final bool isCurrent;

  factory TermInfo.fromMap(Map<String, dynamic> m) => TermInfo(
        id: m['id'] as String,
        name: m['name'] as String,
        number: (m['term_number'] as num).toInt(),
        isCurrent: (m['is_current'] as bool?) ?? false,
      );
}

/// Result sheet = one (term, class, subject). Moves draft -> submitted -> approved -> published.
class SheetInfo {
  const SheetInfo({required this.id, required this.status, this.returnNote});

  final String id;
  final String status;
  final String? returnNote;

  factory SheetInfo.fromMap(Map<String, dynamic> m) => SheetInfo(
        id: m['id'] as String,
        status: m['status'] as String,
        returnNote: m['return_note'] as String?,
      );

  bool get isDraft => status == 'draft';

  String get label => switch (status) {
        'draft' => 'Not sent yet',
        'submitted' => 'Waiting for approval',
        'approved' => 'Approved',
        'published' => 'Shared',
        _ => status,
      };
}

class RosterEntry {
  const RosterEntry({required this.studentId, required this.admissionNumber, required this.name});

  final String studentId;
  final String admissionNumber;
  final String name;

  static RosterEntry? fromMap(Map<String, dynamic> m) {
    final s = m['students'];
    if (s is! Map) return null;
    return RosterEntry(
      studentId: m['student_id'] as String,
      admissionNumber: (s['admission_number'] as String?) ?? '',
      name: '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'.trim(),
    );
  }
}

class ScoreItem {
  const ScoreItem({required this.studentId, this.ca, this.exam, this.total, this.grade, this.remark});

  final String studentId;
  final double? ca;
  final double? exam;
  final double? total;
  final String? grade;
  final String? remark;

  factory ScoreItem.fromMap(Map<String, dynamic> m) => ScoreItem(
        studentId: m['student_id'] as String,
        ca: _num(m['ca_score']),
        exam: _num(m['exam_score']),
        total: _num(m['total']),
        grade: m['grade'] as String?,
        remark: m['remark'] as String?,
      );
}

class Limits {
  const Limits(this.caMax, this.examMax);

  final double caMax;
  final double examMax;
}

// ---------------------------------------------------------------- admin side

/// One result sheet as shown in the administrator's review list.
class SheetSummary {
  const SheetSummary({
    required this.id,
    required this.status,
    required this.className,
    required this.subjectName,
    required this.subjectCode,
    required this.termName,
    required this.sessionName,
    this.returnNote,
  });

  final String id;
  final String status;
  final String className;
  final String subjectName;
  final String subjectCode;
  final String termName;
  final String sessionName;
  final String? returnNote;

  factory SheetSummary.fromMap(Map<String, dynamic> m) {
    final term = (m['terms'] as Map?) ?? const {};
    return SheetSummary(
      id: m['id'] as String,
      status: m['status'] as String,
      className: ((m['classes'] as Map?)?['name'] as String?) ?? '',
      subjectName: ((m['subjects'] as Map?)?['name'] as String?) ?? '',
      subjectCode: ((m['subjects'] as Map?)?['code'] as String?) ?? '',
      termName: (term['name'] as String?) ?? '',
      sessionName: ((term['academic_sessions'] as Map?)?['name'] as String?) ?? '',
      returnNote: m['return_note'] as String?,
    );
  }

  String get statusLabel => switch (status) {
        'draft' => 'Not sent yet',
        'submitted' => 'Waiting for approval',
        'approved' => 'Approved',
        'published' => 'Shared',
        _ => status,
      };
}

class ReviewItem {
  const ReviewItem({
    required this.name,
    required this.admissionNumber,
    this.ca,
    this.exam,
    this.total,
    this.grade,
  });

  final String name;
  final String admissionNumber;
  final double? ca;
  final double? exam;
  final double? total;
  final String? grade;

  factory ReviewItem.fromMap(Map<String, dynamic> m) {
    final s = (m['students'] as Map?) ?? const {};
    return ReviewItem(
      name: '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'.trim(),
      admissionNumber: (s['admission_number'] as String?) ?? '',
      ca: _num(m['ca_score']),
      exam: _num(m['exam_score']),
      total: _num(m['total']),
      grade: m['grade'] as String?,
    );
  }
}

// ---------------------------------------------------------------- notifications, report cards, summaries

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    this.entityId,
    this.createdAt,
    this.readAt,
  });

  final String id;
  final String kind;
  final String title;
  final String? body;
  final String? entityId;
  final DateTime? createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  factory NotificationItem.fromMap(Map<String, dynamic> m) => NotificationItem(
        id: m['id'] as String,
        kind: m['kind'] as String,
        title: m['title'] as String,
        body: m['body'] as String?,
        entityId: m['entity_id'] as String?,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '')?.toLocal(),
        readAt: DateTime.tryParse((m['read_at'] as String?) ?? '')?.toLocal(),
      );
}

/// One line of the school's grading scale (grade = highest band whose minimum the total reaches).
class GradeBand {
  const GradeBand({required this.grade, required this.minScore, this.remark});

  final String grade;
  final double minScore;
  final String? remark;

  factory GradeBand.fromMap(Map<String, dynamic> m) => GradeBand(
        grade: m['grade'] as String,
        minScore: _num(m['min_score']) ?? 0,
        remark: m['remark'] as String?,
      );
}

/// Class + subject + term statistics for teachers/admins (approved or shared results only).
class ClassSummaryRow {
  const ClassSummaryRow({
    required this.status,
    required this.termId,
    required this.termName,
    required this.termNumber,
    required this.sessionName,
    required this.classId,
    required this.className,
    required this.subjectName,
    required this.scored,
    this.average,
    this.lowest,
    this.highest,
  });

  final String status;
  final String termId;
  final String termName;
  final int termNumber;
  final String sessionName;
  final String classId;
  final String className;
  final String subjectName;
  final int scored;
  final double? average;
  final double? lowest;
  final double? highest;

  String get termLabel => '$sessionName · $termName';

  factory ClassSummaryRow.fromMap(Map<String, dynamic> m) => ClassSummaryRow(
        status: m['status'] as String,
        termId: m['term_id'] as String,
        termName: m['term_name'] as String,
        termNumber: (m['term_number'] as num).toInt(),
        sessionName: m['session_name'] as String,
        classId: m['class_id'] as String,
        className: m['class_name'] as String,
        subjectName: m['subject_name'] as String,
        scored: (m['scored'] as num?)?.toInt() ?? 0,
        average: _num(m['average']),
        lowest: _num(m['lowest']),
        highest: _num(m['highest']),
      );
}

// ---------------------------------------------------------------- attendance and fees

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 12500 -> "₦12,500" (NGN) or "USD 12,500".
String money(num? value, [String currency = 'NGN']) {
  final v = (value ?? 0).toDouble();
  final whole = v == v.roundToDouble();
  final text = (whole ? v.toStringAsFixed(0) : v.toStringAsFixed(2))
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return currency == 'NGN' ? '₦$text' : '$currency $text';
}

class AttendanceRecord {
  const AttendanceRecord({required this.studentId, required this.date, required this.status, this.note});

  final String studentId;
  final DateTime date;
  final String status; // present | late | absent
  final String? note;

  factory AttendanceRecord.fromMap(Map<String, dynamic> m) => AttendanceRecord(
        studentId: m['student_id'] as String,
        date: DateTime.parse(m['attendance_date'] as String),
        status: m['status'] as String,
        note: m['note'] as String?,
      );

  String get label => switch (status) {
        'present' => 'Present',
        'late' => 'Late',
        'absent' => 'Absent',
        _ => status,
      };
}

class FeeBalance {
  const FeeBalance({
    required this.studentFeeId,
    required this.studentId,
    required this.studentName,
    required this.admissionNumber,
    required this.title,
    required this.categoryName,
    required this.currency,
    required this.sessionName,
    required this.amount,
    required this.paid,
    required this.balance,
    required this.status,
    this.termName,
    this.dueDate,
  });

  final String studentFeeId;
  final String studentId;
  final String studentName;
  final String admissionNumber;
  final String title;
  final String categoryName;
  final String currency;
  final String sessionName;
  final String? termName;
  final double amount;
  final double paid;
  final double balance;
  final String status; // paid | part_paid | overdue | unpaid
  final String? dueDate;

  factory FeeBalance.fromMap(Map<String, dynamic> m) => FeeBalance(
        studentFeeId: m['student_fee_id'] as String,
        studentId: m['student_id'] as String,
        studentName: '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
        admissionNumber: (m['admission_number'] as String?) ?? '',
        title: m['title'] as String,
        categoryName: (m['category_name'] as String?) ?? '',
        currency: (m['currency'] as String?) ?? 'NGN',
        sessionName: (m['session_name'] as String?) ?? '',
        termName: m['term_name'] as String?,
        amount: _num(m['amount']) ?? 0,
        paid: _num(m['paid']) ?? 0,
        balance: _num(m['balance']) ?? 0,
        status: m['status'] as String,
        dueDate: m['due_date'] as String?,
      );

  String get statusLabel => switch (status) {
        'paid' => 'Paid',
        'part_paid' => 'Part paid',
        'overdue' => 'Overdue',
        _ => 'Not paid',
      };
}

class FeePayment {
  const FeePayment({
    required this.id,
    required this.amount,
    required this.paidOn,
    required this.method,
    required this.source,
    this.reference,
    this.note,
    this.reversedAt,
    this.reversalReason,
  });

  final String id;
  final double amount;
  final String paidOn;
  final String method;
  final String source; // school_recorded | gateway_verified
  final String? reference;
  final String? note;
  final DateTime? reversedAt;
  final String? reversalReason;

  bool get isReversed => reversedAt != null;
  bool get isOnline => source == 'gateway_verified';

  factory FeePayment.fromMap(Map<String, dynamic> m) => FeePayment(
        id: m['id'] as String,
        amount: _num(m['amount']) ?? 0,
        paidOn: m['paid_on'] as String,
        method: m['method'] as String,
        source: m['source'] as String,
        reference: m['reference'] as String?,
        note: m['note'] as String?,
        reversedAt: DateTime.tryParse((m['reversed_at'] as String?) ?? '')?.toLocal(),
        reversalReason: m['reversal_reason'] as String?,
      );

  String get methodLabel => switch (method) {
        'cash' => 'Cash',
        'bank_transfer' => 'Bank transfer',
        'pos' => 'POS',
        'cheque' => 'Cheque',
        _ => 'Other',
      };
}

class FeeCategory {
  const FeeCategory({required this.id, required this.name, required this.isActive, this.description});

  final String id;
  final String name;
  final bool isActive;
  final String? description;

  factory FeeCategory.fromMap(Map<String, dynamic> m) => FeeCategory(
        id: m['id'] as String,
        name: m['name'] as String,
        isActive: (m['is_active'] as bool?) ?? true,
        description: m['description'] as String?,
      );
}

class FeeChargeRow {
  const FeeChargeRow({
    required this.id,
    required this.title,
    required this.amount,
    required this.currency,
    required this.categoryName,
    required this.scope,
    required this.sessionName,
    this.termName,
    this.dueDate,
  });

  final String id;
  final String title;
  final double amount;
  final String currency;
  final String categoryName;
  final String scope; // class name or student name
  final String sessionName;
  final String? termName;
  final String? dueDate;

  factory FeeChargeRow.fromMap(Map<String, dynamic> m) {
    final cls = (m['classes'] as Map?)?['name'] as String?;
    final st = m['students'] as Map?;
    return FeeChargeRow(
      id: m['id'] as String,
      title: m['title'] as String,
      amount: _num(m['amount']) ?? 0,
      currency: (m['currency'] as String?) ?? 'NGN',
      categoryName: ((m['fee_categories'] as Map?)?['name'] as String?) ?? '',
      scope: cls ?? '${st?['first_name'] ?? ''} ${st?['last_name'] ?? ''}'.trim(),
      sessionName: ((m['academic_sessions'] as Map?)?['name'] as String?) ?? '',
      termName: (m['terms'] as Map?)?['name'] as String?,
      dueDate: m['due_date'] as String?,
    );
  }
}

// ---------------------------------------------------------------- messaging and meetings

String formatTime(DateTime? d) =>
    d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class ThreadSummary {
  const ThreadSummary({
    required this.threadId,
    required this.studentName,
    required this.otherName,
    required this.otherRole,
    required this.status,
    required this.unread,
    this.subject,
    this.lastBody,
    this.lastMessageAt,
  });

  final String threadId;
  final String studentName;
  final String otherName;
  final String otherRole; // teacher | parent
  final String status; // open | closed
  final int unread;
  final String? subject;
  final String? lastBody;
  final DateTime? lastMessageAt;

  bool get isClosed => status == 'closed';

  factory ThreadSummary.fromMap(Map<String, dynamic> m) => ThreadSummary(
        threadId: m['thread_id'] as String,
        studentName: (m['student_name'] as String?) ?? '',
        otherName: (m['other_name'] as String?) ?? '',
        otherRole: (m['other_role'] as String?) ?? '',
        status: (m['status'] as String?) ?? 'open',
        unread: (m['unread'] as num?)?.toInt() ?? 0,
        subject: m['subject'] as String?,
        lastBody: m['last_body'] as String?,
        lastMessageAt: DateTime.tryParse((m['last_message_at'] as String?) ?? '')?.toLocal(),
      );
}

class ChatMessage {
  const ChatMessage({required this.id, required this.senderId, required this.body, this.createdAt});

  final String id;
  final String senderId;
  final String body;
  final DateTime? createdAt;

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
        id: m['id'] as String,
        senderId: m['sender_id'] as String,
        body: m['body'] as String,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '')?.toLocal(),
      );
}

/// Someone the signed-in parent/teacher is allowed to start a conversation with.
class MessageContact {
  const MessageContact({
    required this.studentId,
    required this.studentName,
    required this.otherUserId,
    required this.otherName,
    required this.detail,
  });

  final String studentId;
  final String studentName;
  final String otherUserId;
  final String otherName;
  final String detail;

  factory MessageContact.fromMap(Map<String, dynamic> m) => MessageContact(
        studentId: m['student_id'] as String,
        studentName: (m['student_name'] as String?) ?? '',
        otherUserId: m['other_user_id'] as String,
        otherName: (m['other_name'] as String?) ?? '',
        detail: (m['detail'] as String?) ?? '',
      );
}

class MessageReportRow {
  const MessageReportRow({
    required this.id,
    required this.status,
    required this.reason,
    required this.threadId,
    required this.messageBody,
    required this.senderId,
    required this.senderName,
    required this.reporterName,
    required this.studentName,
    required this.parentName,
    required this.teacherName,
    this.createdAt,
    this.resolutionNote,
  });

  final String id;
  final String status;
  final String reason;
  final String threadId;
  final String messageBody;
  final String senderId;
  final String senderName;
  final String reporterName;
  final String studentName;
  final String parentName;
  final String teacherName;
  final DateTime? createdAt;
  final String? resolutionNote;

  factory MessageReportRow.fromMap(Map<String, dynamic> m) => MessageReportRow(
        id: m['report_id'] as String,
        status: m['status'] as String,
        reason: m['reason'] as String,
        threadId: m['thread_id'] as String,
        messageBody: (m['message_body'] as String?) ?? '',
        senderId: m['sender_id'] as String,
        senderName: (m['sender_name'] as String?) ?? '',
        reporterName: (m['reporter_name'] as String?) ?? '',
        studentName: (m['student_name'] as String?) ?? '',
        parentName: (m['parent_name'] as String?) ?? '',
        teacherName: (m['teacher_name'] as String?) ?? '',
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '')?.toLocal(),
        resolutionNote: m['resolution_note'] as String?,
      );
}

class BlockedUser {
  const BlockedUser({required this.userId, required this.name, this.reason});

  final String userId;
  final String name;
  final String? reason;

  factory BlockedUser.fromMap(Map<String, dynamic> m) => BlockedUser(
        userId: m['user_id'] as String,
        name: ((m['profiles'] as Map?)?['full_name'] as String?)?.trim().isNotEmpty == true
            ? (m['profiles'] as Map)['full_name'] as String
            : 'Unnamed',
        reason: m['reason'] as String?,
      );
}

class MeetingItem {
  const MeetingItem({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.description,
    this.location,
    this.classId,
    this.className,
  });

  final String id;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status; // scheduled | cancelled
  final String? description;
  final String? location;
  final String? classId;
  final String? className;

  bool get isCancelled => status == 'cancelled';
  bool get isOver => endsAt.isBefore(DateTime.now());

  String get whenLabel =>
      '${formatDate(startsAt)}  ·  ${formatTime(startsAt)} to ${formatTime(endsAt)}';

  factory MeetingItem.fromMap(Map<String, dynamic> m) => MeetingItem(
        id: m['id'] as String,
        title: m['title'] as String,
        startsAt: DateTime.parse(m['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(m['ends_at'] as String).toLocal(),
        status: m['status'] as String,
        description: m['description'] as String?,
        location: m['location'] as String?,
        classId: m['class_id'] as String?,
        className: (m['classes'] as Map?)?['name'] as String?,
      );
}

class RsvpRow {
  const RsvpRow({required this.parentName, required this.response, this.note});

  final String parentName;
  final String response; // attending | not_attending | no_response
  final String? note;

  factory RsvpRow.fromMap(Map<String, dynamic> m) => RsvpRow(
        parentName: (m['parent_name'] as String?) ?? 'Unnamed',
        response: (m['response'] as String?) ?? 'no_response',
        note: m['note'] as String?,
      );
}
