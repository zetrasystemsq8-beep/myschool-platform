# Feature expansion plan

Extends the existing system; nothing is rebuilt. Same schemas (`myschool`, `ms_private`), same roles, same RLS pattern
(`school_id` everywhere, helpers in `ms_private`, client writes only through grants + policies + RPCs).

| Group | Features | Status |
|---|---|---|
| 1 | Notifications (+ class-specific notices), report cards (print/PDF), academic progress (student + class level) | **Written, awaiting CI + manual check** (migration 10, test file 02, app screens) |
| 2 | Attendance, fees (school-recorded payments; gateway-verified payments kept separate and not faked) | **Written, awaiting CI + manual check** (migrations 11-12, tests 03-04, app screens) |
| 3 | Parent-teacher messaging (admin-moderated), meetings with RSVP and notifications | Not started |

## Group 1 details
- **Migration `20260101000010`**: `announcements.class_id`; `ms_private.announcement_recipients/visible`; `notifications`
  (read-only for clients except `read_at`); trigger fan-out on first publish (author skipped, no re-notify on edit);
  `class_result_summary` view (staff only; approved/published sheets only).
- **Tests `02_notifications_progress.test.sql`**: class scoping, who is notified, no duplicate on edit, cross-school isolation,
  notification privacy (cannot read/insert/alter others), summary visibility (teacher own subjects, never students/parents).
- **App**: bell + notification centre, class selector on notices, teacher remark per student, report card PDF
  (published results only; bundled DejaVu font), Results/Progress switch, class results summary (teacher/admin).
- **Not included**: push notifications (needs Firebase), result-published notifications (would be noisy), overall
  class-teacher/principal comments on the report card, class position.

## Group 2 details
- **Attendance (migration 11)**: `attendance_records` with `unique (student_id, class_id, attendance_date)`; writes only through the audited
  `mark_attendance()` RPC. Teachers: their classes, today and the last 7 days, inside a school year they teach. Admins: any past day. No future dates.
  Student must be enrolled in that class on that date. Parents/students read their own; `attendance_daily_summary` is staff-only.
- **Fees (migration 12)**: categories, charges (class OR student), per-student fees, payments ledger. Writes only via admin-only audited RPCs
  (`create_fee_charge`, `sync_fee_charge`, `record_fee_payment`, `reverse_fee_payment`). Payments cannot exceed what is owed, cannot be edited or deleted
  (only reversed with a reason). `source` is `school_recorded` for everything the app records; `gateway_verified` rows require provider, reference
  and verification time and can only be created server-side (no gateway is implemented). Balances view shows school-recorded and online money separately.
  Teachers have no fee access; parents/students see only their own.
- **App**: attendance tab (teacher: mark + monthly records; admin: via My school; parent/student: monthly view), fees tab (parent: due/paid/owed + history;
  admin: who owes, fees, fee types, record/reverse payment). Profile moved to a top-bar icon to make room for the new tabs.
- **Not included**: online payment, receipts as PDF, fee waivers/discounts, attendance/fee notifications (kept off to avoid noise), per-subject attendance.
