# Architecture

## Shape
```
Flutter / Web ──HTTPS──► Supabase
                          ├─ Auth (JWT)                      identity
                          ├─ PostgREST  (public schema)      table/view reads + RLS-guarded writes
                          │   └─ RPC: workflow, search       security-definer functions
                          ├─ Edge Functions                  account provisioning, student login
                          └─ Storage                         logos (public), photos/scans (private)
Postgres schemas:  myschool (API surface)   ms_private (helpers, never exposed)   auth/storage (Supabase)
(own schemas => safe to share a Supabase project with other apps; nothing in `public` is touched)
```
The client talks to Postgres directly. Authorization is enforced **in the database** (RLS + constraints +
security-definer functions); Edge Functions exist only for things that need the service role (creating auth
users) or that must run before a session exists (student login).

## Multi-tenancy
Shared database, shared schema, **`school_id` on every tenant row**:
1. `schools` is the tenant root; `school_code` is the public School ID (`^[A-Z0-9][A-Z0-9-]{2,19}$`, unique).
2. Child tables reference parents with **composite foreign keys** `(child_id, school_id)` →
   `parent(id, school_id)`. A result cannot point at another school's term/class/subject/student even if RLS
   were bypassed.
3. `school_id` is immutable (trigger).
4. RLS: every policy calls a helper that checks an **active membership of `auth.uid()` in that exact
   `school_id`** (`ms_private.is_member / is_staff / is_school_admin / has_role`). Default is deny.
5. Users are global (`profiles`); roles are per school (`school_members`), so a parent with children in two
   schools has one login and two memberships. `platform_admin` is a flag on `profiles`, not a school role.

## Roles
| Role | Scope | Can |
|---|---|---|
| student | one school | read own student row, own private data, own **published** results, school announcements |
| parent | school(s) | same, for linked children |
| teacher | one school | read students of classes they teach; enter/submit results only for assigned (class, subject, term) |
| school_admin | one school | manage structure, people links, announcements, approve/publish results, read audit log |
| platform_admin | platform | create/disable schools (RPC), read schools/members/audit; no student or result access |

## Result workflow
A **result sheet** = (term, class, subject). Teachers fill `result_items` (CA + exam per student); total and
grade are computed by trigger from the school's `school_settings` and `grading_scales`.
```
draft ──submit(teacher/admin)──► submitted ──approve(admin)──► approved ──publish(admin)──► published
  ▲            return(admin, reason) ┘            return(admin, reason) ┘      unpublish(admin, reason) → approved
```
Status changes only through RPCs (`submit_/return_/approve_/publish_/unpublish_result_sheet`); a trigger
rejects any other status change. Submission requires a scored item for every non-withdrawn enrolled student.
Items are editable by the assigned teacher/admin in `draft`, by admin only in `submitted`, by nobody afterwards.
Optional `require_separate_approver` forces approver ≠ submitter.

## Future AI scanning (designed, not built)
`script_scans` stores the uploaded photo path (private bucket), a pipeline status
(`uploaded→processing→extracted→reviewed`), engine and `extracted` JSON (score, confidence, raw text).
A future Edge Function/worker (service role) fills `extracted`; the teacher reviews in the app, then writes the
item with `source='ocr'`, `scan_id=…`. From there the normal draft→published flow applies, so OCR output is
never published without human review and admin approval.

## Decisions & trade-offs
- Student auth = Supabase Auth user with a hidden synthetic email + PIN as password, reached via
  `myschool-student-login` (hides the convention, uniform errors). Alternative (custom JWT) rejected: more code, no gain.
- Lifecycle on the sheet, not per student: matches how schools actually submit/approve (per subject per class).
- Student sensitive data split into `student_private` so teachers cannot read it.
- Positions/averages, report-card comments, attendance, fees: out of scope for Part 1.
