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
