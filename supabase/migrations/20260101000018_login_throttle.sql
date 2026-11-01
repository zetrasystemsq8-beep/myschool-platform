-- 18: protects short student PINs from guessing, and closes one small gap.
-- The student-login Edge Function (service role) records wrong attempts here and stops after 5 in 15 minutes.
-- Nothing else can read or write this table: row level security is on and there are no policies.
create table myschool.student_login_attempts (
  id  bigint generated always as identity primary key,
  key text not null,                      -- 'SCHOOL-CODE|admission-number' (normalised)
  ok  boolean not null default false,
  at  timestamptz not null default now()
);
create index student_login_attempts_key_idx on myschool.student_login_attempts (key, at desc);
alter table myschool.student_login_attempts enable row level security;
revoke all on myschool.student_login_attempts from anon, authenticated;

-- try_uuid was created without revoking the default public execute right. Only signed-in users need it.
revoke all on function ms_private.try_uuid(text) from public, anon;
grant execute on function ms_private.try_uuid(text) to authenticated;
