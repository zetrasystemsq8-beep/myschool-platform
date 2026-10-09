# Database

Source of truth: `supabase/migrations/`. All tenant tables carry `school_id`; `UNIQUE (id, school_id)` on
parents enables composite FKs.

## Tables
| Table | Purpose | Key constraints |
|---|---|---|
| `schools` | tenant root; public profile | `school_code` unique + format check; `is_active`, `is_listed` |
| `school_settings` | per-school CA/exam max (must total 100), separate-approver flag | PK = school_id |
| `grading_scales` | grade = highest `min_score` ≤ total | PK (school_id, grade); unique (school_id, min_score) |
| `profiles` | one per auth user; `is_platform_admin` | PK = auth.users.id |
| `school_members` | user ↔ school ↔ role, status, staff fields | unique (school_id, user_id) |
| `students` | minimal student record, optional login `user_id` | unique (school_id, admission_number) |
| `student_private` | DOB, gender, address (admin/self/parent only) | FK (student_id, school_id) |
| `parent_students` | parent ↔ child links | composite FKs both sides |
| `academic_sessions` / `terms` | e.g. 2025/2026 → First Term | one current session / term per school |
| `classes`, `subjects` | per-school catalogue | unique name / code per school |
| `teaching_assignments` | teacher ↔ class ↔ subject ↔ session | gates result entry |
| `enrollments` | student ↔ class ↔ session | unique (student_id, session_id) |
| `result_sheets` | (term, class, subject) + lifecycle + who/when | unique (term, class, subject) |
| `result_items` | CA, exam, total, grade, source, scan link | unique (sheet_id, student_id) |
| `script_scans` | future OCR pipeline records | private bucket path, status, extracted JSON |
| `announcements` | title, body, audience, status, timestamps | published ⇒ published_at |
| `audit_logs` | append-only trail | update/delete blocked by trigger |

## Behaviour implemented in the database
- Triggers: `updated_at`; immutable `school_id`; role checks (student/parent/teacher links must hold that
  role in the same school); score ≤ maximum, total + grade computed, student must be enrolled in the sheet's
  class for the term's session; sheet status guard; announcement author/published_at stamping.
- Audit: automatic row-level audit on `result_items`, `announcements`, `school_members`, `students`,
  `teaching_assignments`, `school_settings`, `grading_scales`; workflow RPCs write `result_sheet.submitted |
  returned | approved | published | unpublished`; `create_school`, `set_school_status`, and account provisioning
  also log. Metadata holds old/new values.
- Deletion: students/enrollments/results use `ON DELETE RESTRICT` (history is never silently lost);
  schools should be deactivated, not deleted (audit rows are append-only).

## Read model
`myschool.published_results` (security_invoker view): one row per published item with session, term, class,
subject, scores, grade. RLS of the caller decides whose rows appear.

## Changing grading/limits
Changing `ca_max/exam_max` or the grading scale does not recompute existing items; do it between terms.
