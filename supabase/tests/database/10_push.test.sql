-- pgTAP: phone push tokens.
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

create schema if not exists tests;
grant usage on schema tests to anon, authenticated;
create or replace function tests.act_as(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create or replace function tests.act_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('role', 'anon', true);
end $$;
grant execute on function tests.act_as(uuid), tests.act_anon() to anon, authenticated;

select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');   -- parent
select lives_ok($$select myschool.register_device_token('token-parent-phone-aaaaaaaaaaaaaaaaaaaa', 'android')$$, 'a signed-in user registers their phone');
select throws_ok($$select * from myschool.device_tokens$$, '42501', null, 'the token table cannot be read by clients');
select throws_ok($$insert into myschool.device_tokens (user_id, token) values ('aaaaaaaa-4000-0000-0000-000000000001', 'token-direct-insert-aaaaaaaaaaaaaaaa')$$, '42501', null, 'and cannot be written directly');
select throws_ok($$select myschool.register_device_token('short', 'android')$$, '23514', null, 'an obviously invalid token is refused');
reset role;
select is((select count(*)::int from myschool.device_tokens where user_id = 'aaaaaaaa-4000-0000-0000-000000000001'), 1, 'one token stored');

select tests.act_as('aaaaaaaa-3000-0000-0000-000000000001');   -- Ada picks up the same phone
select lives_ok($$select myschool.register_device_token('token-parent-phone-aaaaaaaaaaaaaaaaaaaa', 'android')$$, 'the same phone can sign in as someone else');
reset role;
select is((select user_id::text from myschool.device_tokens where token = 'token-parent-phone-aaaaaaaaaaaaaaaaaaaa'), 'aaaaaaaa-3000-0000-0000-000000000001', 'the token moves to the new user');
select is((select count(*)::int from myschool.device_tokens where token = 'token-parent-phone-aaaaaaaaaaaaaaaaaaaa'), 1, 'and is never duplicated');

select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');   -- the parent cannot remove Ada's token
select lives_ok($$select myschool.remove_device_token('token-parent-phone-aaaaaaaaaaaaaaaaaaaa')$$, 'removing someone else''s token matches nothing');
reset role;
select is((select count(*)::int from myschool.device_tokens where token = 'token-parent-phone-aaaaaaaaaaaaaaaaaaaa'), 1, 'so it is still there');
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000001');
select lives_ok($$select myschool.remove_device_token('token-parent-phone-aaaaaaaaaaaaaaaaaaaa')$$, 'the owner removes their token on sign-out');
reset role;
select is((select count(*)::int from myschool.device_tokens where token = 'token-parent-phone-aaaaaaaaaaaaaaaaaaaa'), 0, 'it is gone');

select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');   -- teacher with many phones
select lives_ok($$select myschool.register_device_token('token-teacher-phone-' || lpad(i::text, 3, '0') || '-xxxxxxxxxxxx', 'android') from generate_series(1, 12) i$$, 'twelve phones are registered');
reset role;
select is((select count(*)::int from myschool.device_tokens where user_id = 'aaaaaaaa-2000-0000-0000-000000000001'), 10, 'only the 10 most recent are kept');

select tests.act_anon();
select throws_ok($$select myschool.register_device_token('token-anonymous-aaaaaaaaaaaaaaaaaaaaaa', 'android')$$, '42501', null, 'anonymous visitors cannot register tokens');
reset role;

select * from finish();
rollback;
