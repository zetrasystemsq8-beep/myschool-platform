-- 05: announcements and the append-only audit log

create table public.announcements (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null references public.schools (id) on delete cascade,
  author_id  uuid references public.profiles (id) on delete set null,
  title      text not null check (char_length(title) between 1 and 200),
  body       text not null check (char_length(body) <= 10000),
  audience   public.announcement_audience not null default 'all',
  status     public.announcement_status not null default 'draft',
  published_at timestamptz,
  expires_at   timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status <> 'published' or published_at is not null)
);
create index announcements_feed_idx on public.announcements (school_id, published_at desc) where status = 'published';

create table public.audit_logs (
  id          bigint generated always as identity primary key,
  school_id   uuid references public.schools (id) on delete cascade, -- null = platform-level event
  actor_id    uuid,                 -- auth user id; null when done by service role / system
  actor_role  text,
  action      text not null,        -- e.g. 'result_sheet.published', 'result_item.updated'
  entity_type text not null,
  entity_id   uuid,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index audit_logs_school_time_idx on public.audit_logs (school_id, created_at desc);
create index audit_logs_entity_idx on public.audit_logs (entity_type, entity_id);
