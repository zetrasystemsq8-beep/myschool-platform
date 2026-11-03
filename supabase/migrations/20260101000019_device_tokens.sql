-- 19: phone push notifications. Each signed-in phone registers a Firebase token; the send-push Edge Function
-- (service role) reads them. Clients can only use the two functions below: the table itself is closed.
create table myschool.device_tokens (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references myschool.profiles (id) on delete cascade,
  token        text not null unique check (char_length(token) between 20 and 4096),
  platform     text not null default 'android' check (platform in ('android', 'ios', 'web')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index device_tokens_user_idx on myschool.device_tokens (user_id);
alter table myschool.device_tokens enable row level security;     -- no policies: only the functions and the service role
revoke all on myschool.device_tokens from anon, authenticated;

-- Registers (or re-assigns) this phone's token to the signed-in user. A phone that changes user is moved, never duplicated.
-- At most 10 phones per person are kept (the least recently used are dropped).
create or replace function myschool.register_device_token(p_token text, p_platform text default 'android')
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  insert into myschool.device_tokens (user_id, token, platform)
  values (auth.uid(), p_token, coalesce(nullif(p_platform, ''), 'android'))
  on conflict (token) do update set user_id = auth.uid(), last_seen_at = now(), platform = excluded.platform;
  delete from myschool.device_tokens
   where user_id = auth.uid()
     and id not in (select id from myschool.device_tokens where user_id = auth.uid() order by last_seen_at desc limit 10);
end $$;

create or replace function myschool.remove_device_token(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from myschool.device_tokens where token = p_token and user_id = auth.uid();
end $$;

revoke all on function myschool.register_device_token(text, text), myschool.remove_device_token(text) from public, anon, authenticated;
grant execute on function myschool.register_device_token(text, text), myschool.remove_device_token(text) to authenticated;

notify pgrst, 'reload schema';
