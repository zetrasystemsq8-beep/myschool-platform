-- 15: audit changes to a school's own profile (name, motto, logo, contact details ...).
-- The audit trigger now also knows that, on the schools table, the school id is the row's own id,
-- so the entries are visible to that school's administrators.
create or replace function ms_private.audit_row() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_row jsonb; v_old jsonb; v_changed jsonb; v_school uuid; v_id uuid; v_action text;
begin
  v_action := tg_argv[0] || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end;
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_school := coalesce(nullif(v_row ->> 'school_id', '')::uuid,
                       case when tg_table_name = 'schools' then nullif(v_row ->> 'id', '')::uuid end);
  v_id := coalesce(nullif(v_row ->> 'id', ''), nullif(v_row ->> 'school_id', ''))::uuid;
  if tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    select jsonb_object_agg(n.key, jsonb_build_object('old', v_old -> n.key, 'new', n.value)) into v_changed
      from jsonb_each(v_row) n
     where n.key <> 'updated_at' and (v_old -> n.key) is distinct from n.value;
    if v_changed is not null then
      perform ms_private.write_audit(v_school, v_action, tg_argv[0], v_id, jsonb_build_object('changed', v_changed));
    end if;
    return new;
  elsif tg_op = 'INSERT' then
    perform ms_private.write_audit(v_school, v_action, tg_argv[0], v_id, jsonb_build_object('after', v_row));
    return new;
  else
    perform ms_private.write_audit(v_school, v_action, tg_argv[0], v_id, jsonb_build_object('before', v_row));
    return old;
  end if;
end $$;
revoke all on function ms_private.audit_row() from public, anon, authenticated;

create trigger audit_schools after update on myschool.schools
  for each row execute function ms_private.audit_row('school');
