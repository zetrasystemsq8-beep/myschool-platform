# Feature expansion plan

Extends the existing system; nothing is rebuilt. Same schemas (`myschool`, `ms_private`), same roles, same RLS pattern
(`school_id` everywhere, helpers in `ms_private`, client writes only through grants + policies + RPCs).

| Group | Features | Status |
|---|---|---|
| 1 | Notifications (+ class-specific notices), report cards (print/PDF), academic progress (student + class level) | **Written, awaiting CI + manual check** (migration 10, test file 02, app screens) |
| 2 | Attendance, fees (school-recorded payments; gateway-verified payments kept separate and not faked) | Not started |
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
