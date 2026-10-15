-- 14: parent-teacher meetings. Admins schedule; parents (of the class, or all) and teachers see them; parents RSVP.
create table myschool.meetings (
  id          uuid primary key default gen_random_uuid(),
  school_id   uuid not null references myschool.schools (id) on delete cascade,
  title       text not null check (char_length(title) between 2 and 120),
  description text check (description is null or char_length(description) <= 2000),
  starts_at   timestamptz not null,
  ends_at     timestamptz not null,
  location    text check (location is null or char_length(location) <= 200),
  class_id    uuid,                                   -- null = every parent in the school
  status      text not null default 'scheduled' check (status in ('scheduled', 'cancelled')),
  created_by  uuid default auth.uid() references myschool.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (id, school_id),
  check (ends_at > starts_at),
  foreign key (class_id, school_id) references myschool.classes (id, school_id) on delete set null (class_id)
);
create index meetings_school_time_idx on myschool.meetings (school_id, starts_at);
create trigger touch_updated_at before update on myschool.meetings
  for each row execute function ms_private.touch_updated_at();
create trigger forbid_school_change before update on myschool.meetings
  for each row execute function ms_private.forbid_school_change();
create trigger audit_meetings after insert or update or delete on myschool.meetings
  for each row execute function ms_private.audit_row('meeting');

create table myschool.meeting_rsvps (
  meeting_id     uuid not null,
  school_id      uuid not null,
  parent_user_id uuid not null,
  response       text not null check (response in ('attending', 'not_attending')),
  note           text check (note is null or char_length(note) <= 200),
  responded_at   timestamptz not null default now(),
  primary key (meeting_id, parent_user_id),
  foreign key (meeting_id, school_id) references myschool.meetings (id, school_id) on delete cascade,
  foreign key (school_id, parent_user_id) references myschool.school_members (school_id, user_id) on delete cascade
);
create trigger rsvp_parent_role before insert on myschool.meeting_rsvps
  for each row execute function ms_private.assert_member_role('parent_user_id', 'parent');

-- Parents of the class (or every parent, if no class) and the staff who teach it (or all staff) may see a meeting.
create or replace function ms_private.meeting_visible(p_school uuid, p_class uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from ms_private.announcement_recipients(p_school, 'parents', p_class) r where r.user_id = auth.uid())
      or exists (select 1 from ms_private.announcement_recipients(p_school, 'staff', p_class) r where r.user_id = auth.uid())
$$;

alter table myschool.meetings      enable row level security;
alter table myschool.meeting_rsvps enable row level security;
create policy meetings_select on myschool.meetings for select to authenticated
  using (ms_private.is_school_admin(school_id) or ms_private.meeting_visible(school_id, class_id));
create policy meetings_insert on myschool.meetings for insert to authenticated
  with check (ms_private.is_school_admin(school_id));
create policy meetings_update on myschool.meetings for update to authenticated
  using (ms_private.is_school_admin(school_id)) with check (ms_private.is_school_admin(school_id));
create policy rsvps_select on myschool.meeting_rsvps for select to authenticated
  using (parent_user_id = (select auth.uid()) or ms_private.is_school_admin(school_id));
-- RSVPs are written only by respond_to_meeting().

-- New / changed / cancelled meetings notify the people it concerns. One notification per meeting until it is read.
create or replace function ms_private.notify_meeting() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_title text; v_when text; v_user uuid;
begin
  if tg_op = 'INSERT' and new.status = 'scheduled' then
    v_title := 'New meeting: ' || new.title;
  elsif tg_op = 'UPDATE' and new.status = 'cancelled' and old.status <> 'cancelled' then
    v_title := 'Meeting cancelled: ' || new.title;
  elsif tg_op = 'UPDATE' and new.status = 'scheduled'
        and (new.starts_at, new.ends_at, new.location) is distinct from (old.starts_at, old.ends_at, old.location) then
    v_title := 'Meeting updated: ' || new.title;
  else
    return null;
  end if;
  v_when := to_char(new.starts_at at time zone coalesce(
              (select s.timezone from myschool.school_settings s where s.school_id = new.school_id), 'Africa/Lagos'),
              'Dy DD Mon YYYY, HH24:MI');
  for v_user in
    select r.user_id from ms_private.announcement_recipients(new.school_id, 'parents', new.class_id) r
    union
    select r.user_id from ms_private.announcement_recipients(new.school_id, 'staff', new.class_id) r
  loop
    continue when v_user is not distinct from new.created_by;
    update myschool.notifications set title = v_title, body = v_when, created_at = now()
     where user_id = v_user and kind = 'meeting' and entity_id = new.id and read_at is null;
    if not found then
      insert into myschool.notifications (school_id, user_id, kind, title, body, entity_type, entity_id)
      values (new.school_id, v_user, 'meeting', v_title, v_when, 'meeting', new.id);
    end if;
  end loop;
  return null;
end $$;
create trigger meetings_notify after insert or update on myschool.meetings
  for each row execute function ms_private.notify_meeting();

create or replace function myschool.respond_to_meeting(p_meeting uuid, p_response text, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare m myschool.meetings;
begin
  select * into m from myschool.meetings where id = p_meeting;
  if m.id is null or not exists (
       select 1 from ms_private.announcement_recipients(m.school_id, 'parents', m.class_id) r where r.user_id = auth.uid()) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if m.status = 'cancelled' then raise exception 'This meeting was cancelled.' using errcode = '55000'; end if;
  if m.ends_at < now() then raise exception 'This meeting is already over.' using errcode = '55000'; end if;
  if p_response not in ('attending', 'not_attending') then
    raise exception 'Choose attending or not attending.' using errcode = '22023';
  end if;
  insert into myschool.meeting_rsvps (meeting_id, school_id, parent_user_id, response, note)
  values (m.id, m.school_id, auth.uid(), p_response, nullif(left(trim(coalesce(p_note, '')), 200), ''))
  on conflict (meeting_id, parent_user_id)
  do update set response = excluded.response, note = excluded.note, responded_at = now();
end $$;

-- Admin: every invited parent with their answer (or no answer).
create or replace function myschool.meeting_rsvp_report(p_meeting uuid)
returns table (parent_user_id uuid, parent_name text, response text, responded_at timestamptz, note text)
language plpgsql stable security definer set search_path = '' as $$
declare m myschool.meetings;
begin
  select * into m from myschool.meetings where id = p_meeting;
  if m.id is null or not ms_private.is_school_admin(m.school_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
  select r.user_id, coalesce(nullif(trim(p.full_name), ''), 'Unnamed'), coalesce(rs.response, 'no_response'), rs.responded_at, rs.note
    from ms_private.announcement_recipients(m.school_id, 'parents', m.class_id) r
    left join myschool.profiles p on p.id = r.user_id
    left join myschool.meeting_rsvps rs on rs.meeting_id = m.id and rs.parent_user_id = r.user_id
   order by 2;
end $$;

revoke all on function ms_private.meeting_visible(uuid, uuid), ms_private.notify_meeting() from public, anon, authenticated;
grant execute on function ms_private.meeting_visible(uuid, uuid) to authenticated;
revoke all on function myschool.respond_to_meeting(uuid, text, text), myschool.meeting_rsvp_report(uuid) from public, anon, authenticated;
grant execute on function myschool.respond_to_meeting(uuid, text, text), myschool.meeting_rsvp_report(uuid) to authenticated;
grant select on myschool.meetings, myschool.meeting_rsvps to authenticated;
grant insert, update on myschool.meetings to authenticated;

notify pgrst, 'reload schema';
