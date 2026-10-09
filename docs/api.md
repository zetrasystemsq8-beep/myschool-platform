# Flutter ↔ Supabase contract

Client setup: `Supabase.initialize(url: SUPABASE_URL, anonKey: SUPABASE_ANON_KEY)`. Never embed the service key.
MySchool lives in its own Postgres schema, so every table/RPC call goes through `final ms = supabase.schema('myschool');`
(`ms.from(...)`, `ms.rpc(...)`). Auth, storage and Edge Functions use the normal `supabase` client. The `myschool` schema must be
listed under Settings → API → Exposed schemas.
All table access goes through `ms.from(...)`; RLS decides what comes back (an empty list can mean
"not allowed"). Errors: Postgres code `42501` = forbidden, `23514` = validation, `55000` = wrong workflow state,
`22023` = missing reason, `23505` = duplicate.

## 1. School discovery (no login)
```dart
final r = await ms.rpc('search_schools', params: {'q': 'christ', 'max_results': 10});
// [{id, school_code, name, motto, logo_path, city, state}]
final p = await ms.rpc('get_public_school', params: {'p_school_code': 'CHR-ADO'});
// [{id, school_code, name, motto, description, logo_path, website, city, state, country}]
final logoUrl = supabase.storage.from('myschool-logos').getPublicUrl(logo_path);
```
Remember the chosen `school_code` / `id` locally; it is only a UI choice – authorization never depends on it.

## 2. Authentication
**Student** (School ID + admission number + PIN) – Edge Function, then adopt the session:
```http
POST {SUPABASE_URL}/functions/v1/myschool-student-login        apikey: <anon key>
{"school_code":"DEMO-A","admission_number":"ADM001","pin":"••••••"}
→ 200 {"session":{"access_token":"…","refresh_token":"…","expires_in":3600,"expires_at":…,"token_type":"bearer"},
       "student":{"id":"…","school_id":"…","school_code":"DEMO-A","admission_number":"ADM001","first_name":"Ada","last_name":"Student"}}
→ 401 {"error":{"code":"invalid_credentials","message":"…"}}   → 403 account_disabled
```
```dart
await supabase.auth.setSession(json['session']['refresh_token']);
```
**Parent / teacher / school admin**: `supabase.auth.signInWithPassword(email:, password:)`.
After any login, load memberships (role per school):
```dart
final m = await ms.from('school_members')
  .select('role, status, schools(id, school_code, name, logo_path)')
  .eq('user_id', supabase.auth.currentUser!.id);   // [{role:'teacher', schools:{…}}]
```
Platform admin: `profiles.is_platform_admin`. Sessions refresh automatically; sign out with `auth.signOut()`.

## 3. School profile (members)
`ms.from('schools').select('*').eq('id', schoolId).single()`; settings: `school_settings`; grading:
`grading_scales` (order by `min_score` desc).

## 4. Student profile
```dart
ms.from('students').select('id, admission_number, first_name, last_name, other_names, status, photo_path,'
  ' enrollments(status, classes(name, level), academic_sessions(name))').eq('user_id', uid).single();
ms.from('student_private').select('date_of_birth, gender').eq('student_id', studentId).single();
```
Parents: `parent_students` → `students` (`.select('student_id, students(*)')`). Photo: signed URL from private
bucket `myschool-student-photos`, path `{school_id}/{student_id}.jpg`.

## 5. Results (student / parent) – published only
```dart
final rows = await ms.from('published_results').select()
  .eq('student_id', studentId).eq('term_id', termId).order('subject_name');
// {item_id, school_id, student_id, session_id, session_name, term_id, term_number, term_name,
//  class_name, subject_id, subject_name, subject_code, ca_score, exam_score, total, grade, remark, published_at}
```
**Previous results**: same view without `term_id`; group by `session_name`, `term_number`. List terms/sessions with
`terms` (select `*, academic_sessions(name)`). Do not compute grades client-side; use `grade`.

## 6. Announcements
```dart
ms.from('announcements').select('id,title,body,audience,published_at')
  .order('published_at', ascending: false).limit(20);   // RLS: published, not expired, audience matches role
```
Admin create: `insert({'school_id':…, 'title':…, 'body':…, 'audience':'all', 'status':'published'})`
(`published_at`/`author_id` set by the database).

## 7. Teacher: result entry & submission
```dart
// my assignments
ms.from('teaching_assignments').select('id, class_id, subject_id, session_id, classes(name), subjects(name)');
// open (or fetch) the sheet
final sheet = await ms.from('result_sheets').insert({'school_id':sid,'term_id':t,'class_id':c,'subject_id':s,
  'created_by': uid}).select().single();            // duplicate (term,class,subject) → 23505: select the existing one
// roster
ms.from('enrollments').select('student_id, students(admission_number, first_name, last_name)')
  .eq('class_id', c).eq('session_id', sess).neq('status','withdrawn');
// scores (upsert per student; total & grade computed by DB)
ms.from('result_items').upsert({'school_id':sid,'sheet_id':sheet['id'],'student_id':st,
  'ca_score':28,'exam_score':41}, onConflict: 'sheet_id,student_id');
await ms.rpc('submit_result_sheet', params: {'p_sheet_id': sheet['id']});   // → updated sheet row
```
Errors: `23514 "N enrolled student(s) have no score yet"`, `23514 "ca_score … exceeds maximum …"`.
After submission the teacher can no longer edit (RLS) – read-only UI when `status != 'draft'`.

## 8. Admin review
```dart
ms.from('result_sheets').select('*, classes(name), subjects(name), terms(name)').eq('status','submitted');
ms.from('result_items').select('*, students(admission_number, first_name, last_name)').eq('sheet_id', id);
await ms.rpc('approve_result_sheet',   params: {'p_sheet_id': id});
await ms.rpc('publish_result_sheet',   params: {'p_sheet_id': id});
await ms.rpc('return_result_sheet',    params: {'p_sheet_id': id, 'p_note': 'Check Ada\'s exam score'});
await ms.rpc('unpublish_result_sheet', params: {'p_sheet_id': id, 'p_reason': 'Wrong class'});
ms.from('audit_logs').select().order('created_at', ascending: false).limit(50);
```
Admin may correct items while a sheet is `submitted`; to change approved/published data: return/unpublish first.

## 9. Provisioning (admin UI) – Edge Function `myschool-provision-user` (Bearer = admin session)
```http
POST /functions/v1/myschool-provision-user
{"action":"create","school_id":"…","role":"student",
 "student":{"admission_number":"2024/017","first_name":"Ada","last_name":"Obi","pin":"482913","class_id":"…","session_id":"…"}}
→ 201 {"user_id":"…","student_id":"…","role":"student"}
{"action":"create","school_id":"…","role":"teacher","email":"t@x.com","password":"min-10-chars","full_name":"…","staff_number":"T-12"}
{"action":"create","school_id":"…","role":"parent","email":"p@x.com","password":"…","link_student_ids":["…"]}
{"action":"reset_password","school_id":"…","user_id":"…","new_password":"…"}
→ 400 weak_password | 403 forbidden | 409 already_exists
```
Platform admin: `rpc('create_school', {p_school_code:'CHR-ADO', p_name:'…', p_motto:…})`, `rpc('set_school_status', {...})`,
then `myschool-provision-user` with `role:"school_admin"` for the first administrator.

## 10. Other
Upload logo: `storage.from('myschool-logos').upload('{school_id}/logo.png', file)` then update `schools.logo_path`.
Not available yet: OCR (tables exist; no processing), push notifications, position/average calculations.
