# Security

## Controls
1. **RLS on every table, default deny**; policies anchored on active membership in the row's `school_id`.
2. **Table + column grants** (`0008_grants.sql`): `anon` has no table access at all (grants only touch the `myschool` schema); `authenticated` cannot
   update `school_code`, `is_active`, `role`, `school_id`, `is_platform_admin`; `result_sheets` has no UPDATE;
   `audit_logs` is SELECT-only.
3. **Composite FKs** make cross-school references impossible even with RLS bypassed.
4. **Helpers live in `ms_private`** (not exposed by the API), `SECURITY DEFINER`, `search_path=''`, always using
   `auth.uid()` – never a caller-supplied user id. `write_audit` and `transition_sheet` are not executable
   by clients; workflow RPCs are the only way to move a sheet.
5. **Public surface for anonymous users** is exactly `search_schools` and `get_public_school`, returning
   name, code, motto, logo path, city/state (+description, website, country on the profile).
6. **Students**: separate `student_private`; teachers see only students in classes they teach; results visible
   only when the sheet is `published` and the row is theirs (or their child's).
7. **Storage**: logos public-read / admin-write per school folder; student photos and script scans private,
   folder 1 = `school_id` checked by policy.
8. **Secrets**: only `.env.example` is committed; `.gitignore` excludes `.env*`. The service-role key exists
   only inside Edge Functions/CI secrets. Flutter gets URL + anon key only.
9. **Signups disabled**: accounts are created by `myschool-provision-user` after verifying the caller is that school's
   admin (or platform admin). Only platform admins create school admins.

## Known limits (be aware)
- Student PIN = Supabase password (min 6). Rely on Supabase Auth rate limits, enable CAPTCHA/attack protection
  in the dashboard, and prefer 8+ character PINs. `myschool-student-login` returns uniform errors.
- Admission numbers differing only by punctuation (`A/1`, `A-1`) normalise to the same login; the second
  creation fails with `already_exists`.
- `myschool-provision-user` and `myschool-student-login` are untested Deno code; the SQL is untested until `scripts/test.sh` runs.
- Teachers' edits after approval require an admin to `return_result_sheet` first (by design).
- OCR is not implemented.

## Production checklist
- Auth: enable CAPTCHA/attack protection and email rate limits. In a shared project do NOT turn signups off (other apps need them); MySchool stays safe because a stray account has no school membership.
- Create first platform admin in SQL editor: add the user in Auth → Users, then run
  `insert into myschool.profiles (id, full_name, is_platform_admin) values ('<uuid>', 'Your Name', true) on conflict (id) do update set is_platform_admin = true;`
  (profiles are NOT auto-created: there is no trigger on auth.users)
- Expose the schema: Settings → API → Exposed schemas → add `myschool`. Never run `seed.sql`.
- Enable PITR/backups; restrict dashboard access; rotate keys if ever leaked.
- Run `supabase test db` in CI on every change to migrations.

## Test coverage (`supabase/tests/database/01_security.test.sql`)
Student of A vs B results · student vs classmate · teacher vs other school · admin vs other school ·
draft invisible · published visible only to owner/parent · anon cannot read tables · search exposes only public
columns, escapes wildcards, hides unlisted schools · no direct status change · audit immutability and entries ·
cross-school FK rejection · privilege-escalation attempts.
