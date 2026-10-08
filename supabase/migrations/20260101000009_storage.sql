-- 09: storage buckets + policies. Object path convention: {school_id}/... (school_id is folder 1).

create or replace function app.try_uuid(p text) returns uuid
language plpgsql immutable set search_path = '' as $$
begin return p::uuid; exception when others then return null; end $$;
grant execute on function app.try_uuid(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('school-logos',   'school-logos',   true,  2097152,  array['image/png', 'image/jpeg', 'image/webp']),
  ('student-photos', 'student-photos', false, 2097152,  array['image/jpeg', 'image/png', 'image/webp']),
  ('script-scans',   'script-scans',   false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do nothing;

-- school-logos: public READ by URL (logos are intentionally public); only that school's admin writes
create policy logos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'school-logos' and app.is_school_admin(app.try_uuid((storage.foldername(name))[1])));
create policy logos_update on storage.objects for update to authenticated
  using (bucket_id = 'school-logos' and app.is_school_admin(app.try_uuid((storage.foldername(name))[1])));
create policy logos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'school-logos' and app.is_school_admin(app.try_uuid((storage.foldername(name))[1])));

-- student-photos: path {school_id}/{student_id}.jpg ; admin writes; admin, the student, parents read
create policy photos_select on storage.objects for select to authenticated
  using (bucket_id = 'student-photos'
         and (app.is_school_admin(app.try_uuid((storage.foldername(name))[1]))
              or app.is_self_or_parent_of(app.try_uuid(split_part((storage.filename(name)), '.', 1)))));
create policy photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'student-photos' and app.is_school_admin(app.try_uuid((storage.foldername(name))[1])));
create policy photos_update on storage.objects for update to authenticated
  using (bucket_id = 'student-photos' and app.is_school_admin(app.try_uuid((storage.foldername(name))[1])));
create policy photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'student-photos' and app.is_school_admin(app.try_uuid((storage.foldername(name))[1])));

-- script-scans (future OCR): staff of the school upload; uploader or school admin read
create policy scans_obj_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'script-scans' and app.is_staff(app.try_uuid((storage.foldername(name))[1])));
create policy scans_obj_select on storage.objects for select to authenticated
  using (bucket_id = 'script-scans'
         and (app.is_school_admin(app.try_uuid((storage.foldername(name))[1])) or owner_id = (select auth.uid())::text));
