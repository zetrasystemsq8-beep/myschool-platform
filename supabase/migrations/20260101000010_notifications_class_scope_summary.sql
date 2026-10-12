-- 10: in-app notifications, class-specific announcements, class result summary.
-- Extends the existing announcements/results system; nothing is rebuilt.

-- ---------------------------------------------------------------- class-specific announcements
alter table myschool.announcements add column class_id uuid;
alter table myschool.announcements
  add constraint announcements_class_fk foreign key (class_id, school_id)
  references myschool.classes (id, school_id) on delete set null (class_id);
create index announcements_class_idx on myschool.announcements (class_id) where class_id is not null;

-- Who an announcement is meant for. School-wide (class null): the audience rule only.
-- Class-specific: additionally students in that class (current school year), their parents,
-- teachers assigned to that class, and school admins.
create or replace function ms_private.announcement_recipients(
  p_school uuid, p_audience myschool.announcement_audience, p_class uuid)
returns table (user_id uuid)
language sql stable security definer set search_path = '' as $$
  select m.user_id
  from myschool.school_members m
  join myschool.schools s on s.id = m.school_id and s.is_active
  where m.school_id = p_school and m.status = 'active'
    and (p_audience = 'all'
         or (p_audience = 'students' and m.role = 'student')
         or (p_audience = 'parents'  and m.role = 'parent')
         or (p_audience = 'staff'    and m.role in ('teacher', 'school_admin')))
    and (p_class is null
         or m.role = 'school_admin'
         or (m.role = 'student' and exists (
               select 1 from myschool.students st
               join myschool.enrollments e on e.student_id = st.id
               join myschool.academic_sessions cs on cs.id = e.session_id and cs.is_current
               where st.user_id = m.user_id and e.class_id = p_class and e.status <> 'withdrawn'))
         or (m.role = 'parent' and exists (
               select 1 from myschool.parent_students ps
               join myschool.enrollments e on e.student_id = ps.student_id
               join myschool.academic_sessions cs on cs.id = e.session_id and cs.is_current
               where ps.parent_user_id = m.user_id and ps.school_id = p_school
                 and e.class_id = p_class and e.status <> 'withdrawn'))
         or (m.role = 'teacher' and exists (
               select 1 from myschool.teaching_assignments ta
               join myschool.academic_sessions cs on cs.id = ta.session_id and cs.is_current
               where ta.teacher_user_id = m.user_id and ta.class_id = p_class)))
$$;

create or replace function ms_private.announcement_visible(
  p_school uuid, p_audience myschool.announcement_audience, p_class uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from ms_private.announcement_recipients(p_school, p_audience, p_class) r
    where r.user_id = auth.uid())
$$;

revoke all on function ms_private.announcement_recipients(uuid, myschool.announcement_audience, uuid)
  from public, anon, authenticated;
revoke all on function ms_private.announcement_visible(uuid, myschool.announcement_audience, uuid)
  from public, anon, authenticated;
grant execute on function ms_private.announcement_visible(uuid, myschool.announcement_audience, uuid)
  to authenticated;

drop policy announcements_select on myschool.announcements;
create policy announcements_select on myschool.announcements for select to authenticated
  using (ms_private.is_school_admin(school_id)
         or (status = 'published' and (expires_at is null or expires_at > now())
             and ms_private.announcement_visible(school_id, audience, class_id)));

-- ---------------------------------------------------------------- notifications (in-app only)
create table myschool.notifications (
  id          uuid primary key default gen_random_uuid(),
  school_id   uuid not null references myschool.schools (id) on delete cascade,
  user_id     uuid not null references myschool.profiles (id) on delete cascade,
  kind        text not null check (char_length(kind) between 1 and 30),  -- 'announcement', later 'meeting', ...
  title       text not null,
  body        text,
  entity_type text,
  entity_id   uuid,
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);
create index notifications_user_idx on myschool.notifications (user_id, created_at desc);
create index notifications_unread_idx on myschool.notifications (user_id) where read_at is null;

alter table myschool.notifications enable row level security;
create policy notifications_select on myschool.notifications for select to authenticated
  using (user_id = (select auth.uid()) and ms_private.is_member(school_id));
create policy notifications_update on myschool.notifications for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
grant select on myschool.notifications to authenticated;
grant update (read_at) on myschool.notifications to authenticated;   -- nothing else is editable
-- No INSERT/DELETE for clients: rows are created only by database triggers.

-- Created once, when an announcement becomes published (not on later edits). The author is skipped.
create or replace function ms_private.notify_announcement() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'published'
     and (tg_op = 'INSERT' or old.status is distinct from 'published')
     and (new.expires_at is null or new.expires_at > now()) then
    insert into myschool.notifications (school_id, user_id, kind, title, body, entity_type, entity_id)
    select new.school_id, r.user_id, 'announcement', new.title, left(new.body, 140), 'announcement', new.id
    from ms_private.announcement_recipients(new.school_id, new.audience, new.class_id) r
    where r.user_id is distinct from new.author_id;
  end if;
  return null;
end $$;
revoke all on function ms_private.notify_announcement() from public, anon, authenticated;
create trigger announcements_notify after insert or update of status on myschool.announcements
  for each row execute function ms_private.notify_announcement();

-- ---------------------------------------------------------------- class-level progress (staff only)
-- Per class + subject + term: how many scored, average, lowest, highest.
-- Only approved/published sheets; security_invoker means teachers only get their own subjects.
create view myschool.class_result_summary with (security_invoker = true) as
select sh.school_id, sh.id as sheet_id, sh.status,
       sh.term_id, t.name as term_name, t.term_number,
       ses.id as session_id, ses.name as session_name,
       sh.class_id, c.name as class_name,
       sh.subject_id, sub.name as subject_name,
       count(i.total)::int as scored,
       round(avg(i.total), 1) as average,
       min(i.total) as lowest,
       max(i.total) as highest
  from myschool.result_sheets sh
  join myschool.terms t on t.id = sh.term_id
  join myschool.academic_sessions ses on ses.id = t.session_id
  join myschool.classes c on c.id = sh.class_id
  join myschool.subjects sub on sub.id = sh.subject_id
  left join myschool.result_items i on i.sheet_id = sh.id
 where sh.status in ('approved', 'published')
   and ms_private.is_staff(sh.school_id)
 group by sh.school_id, sh.id, sh.status, sh.term_id, t.name, t.term_number,
          ses.id, ses.name, sh.class_id, c.name, sh.subject_id, sub.name;
grant select on myschool.class_result_summary to authenticated;

notify pgrst, 'reload schema';
