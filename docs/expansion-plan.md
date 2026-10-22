# Feature expansion plan

Extends the existing system; nothing is rebuilt. Same schemas (`myschool`, `ms_private`), same roles, same RLS pattern
(`school_id` everywhere, helpers in `ms_private`, client writes only through grants + policies + RPCs).

| Group | Features | Status |
|---|---|---|
| 1 | Notifications (+ class-specific notices), report cards (print/PDF), academic progress (student + class level) | **Written, awaiting CI + manual check** (migration 10, test file 02, app screens) |
| 2 | Attendance, fees (school-recorded payments; gateway-verified payments kept separate and not faked) | **Written, awaiting CI + manual check** (migrations 11-12, tests 03-04, app screens) |
| 3 | Parent-teacher messaging (admin-moderated), meetings with RSVP and notifications | **Written, awaiting CI + manual check** (migrations 13-14, tests 05-06, app screens) |

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

## Group 3 details
- **Messaging (migration 13)**: one private conversation per (student, parent, teacher). Allowed only when the parent is linked to the student
  and the teacher teaches the student's class in the current school year (checked when starting AND on every send). No direct writes: everything goes
  through `start_message_thread`, `send_message`, `mark_thread_read`, `report_message`. Admins cannot browse conversations; a conversation becomes readable
  to the school's admins only after someone reports it. Admins can resolve reports (optionally closing the conversation), mute a person, and switch
  messaging off for the school (`school_settings.messaging_enabled`). Limit: 30 messages per person per hour, 2000 characters each.
  One notification per conversation until read (no message text in notifications).
- **Meetings (migration 14)**: admins schedule (direct insert/update under RLS, audited); visible to parents of the class (or all parents) and the teachers
  concerned; parents RSVP through `respond_to_meeting` (not for cancelled or finished meetings); admins see answers via `meeting_rsvp_report`.
  New / changed / cancelled meetings notify the people concerned (one notification per meeting until read).
- **App**: bottom bar is now Home + role tabs + **More** (Notices, Meetings, Messages, Message moderation, Profile).
- **Not included**: push notifications, attachments in messages, group chats, meeting reminders before the date.

## Feature 1 of the final list: school profile and settings
- **App**: My school > School profile & settings: logo upload (public bucket, this school's admin only), school details, test/exam split
  (always totals 100), grading scale editor (keep one grade from 0), "a different person must approve" switch. The updated name/logo refreshes
  everywhere without restarting.
- **Migration 15**: audits profile changes and makes them visible to that school's admins. Tests: `07_school_settings.test.sql`.
- Existing results keep their saved totals and grades when the split or the scale changes.

## Features 2 and 3 of the final list: new school year, student status, spreadsheet import
- **Migrations 16-17**: new student status `transferred`; `set_student_status` (sign-in follows status, leavers drop off class lists, graduates keep access
  to old results); `promote_class` (per class: move up / repeat / graduate, safe to re-run); `copy_teaching_assignments`. All admin-only and audited.
  Tests: `08_promotion.test.sql`.
- **App (My school)**: "New school year" (from/to year, destination per class with a suggested next class, repeaters, keep teachers, make current),
  "Import students" (CSV file or pasted text; checks classes, duplicates, PIN and email rules; generates PINs/passwords; printable login list), and
  "Change status" on a student.
- **Import limits**: 300 rows per import; a parent email that already has an account must be linked manually; logins are shown once and never stored.
