-- 09: storage buckets + policies. Object path convention: {school_id}/... (school_id is folder 1).

create or replace function ms_private.try_uuid(p text) returns uuid
language plpgsql immutable set search_path = '' as $$
begin return p::uuid; exception when others then return null; end $$;
grant execute on function ms_private.try_uuid(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('myschool-logos',   'myschool-logos',   true,  2097152,  array['image/png', 'image/jpeg', 'image/webp']),
  ('myschool-student-photos', 'myschool-student-photos', false, 2097152,  array['image/jpeg', 'image/png', 'image/webp']),
  ('myschool-script-scans',   'myschool-script-scans',   false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do nothing;

-- school-logos: public READ by URL (logos are intentionally public); only that school's admin writes
create policy myschool_logos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'myschool-logos' and ms_private.is_school_admin(ms_private.try_uuid((storage.foldername(name))[1])));
create policy myschool_logos_update on storage.objects for update to authenticated
  using (bucket_id = 'myschool-logos' and ms_private.is_school_admin(ms_private.try_uuid((storage.foldername(name))[1])));
create policy myschool_logos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'myschool-logos' and ms_private.is_school_admin(ms_private.try_uuid((storage.foldername(name))[1])));

-- student-photos: path {school_id}/{student_id}.jpg ; admin writes; admin, the student, parents read
create policy myschool_photos_select on storage.objects for select to authenticated
  using (bucket_id = 'myschool-student-photos'
         and (ms_private.is_school_admin(ms_private.try_uuid((storage.foldername(name))[1]))
              or ms_private.is_self_or_parent_of(ms_private.try_uuid(split_part((storage.filename(name)), '.', 1)))));
create policy myschool_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'myschool-student-photos' and ms_private.is_school_admin(ms_private.try_uuid((storage.foldername(name))[1])));
create policy myschool_photos_update on storage.objects for update to authenticated
  using (bucket_id = 'myschool-student-photos' and ms_private.is_school_admin(ms_private.try_uuid((storage.foldername(name))[1])));
create policy myschool_photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'myschool-student-photos' and ms_private.is_school_admin(ms_private.try_uuid((storage.foldername(name))[1])));

-- script-scans (future OCR): staff of the school upload; uploader or school admin read
create policy myschool_scans_obj_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'myschool-script-scans' and ms_private.is_staff(ms_private.try_uuid((storage.foldername(name))[1])));
create policy myschool_scans_obj_select on storage.objects for select to authenticated
  using (bucket_id = 'myschool-script-scans'
         and (ms_private.is_school_admin(ms_private.try_uuid((storage.foldername(name))[1])) or owner_id = (select auth.uid())::text));
