// POST /functions/v1/myschool-provision-user   (JWT required)
// Creates login accounts server-side. Clients can never create memberships themselves.
//
// action "create":
//   { action:"create", school_id, role:"student"|"teacher"|"parent"|"school_admin",
//     full_name?, email?, password?,                       // teacher/parent/school_admin
//     staff_number?, job_title?,                           // staff
//     student?: { admission_number, first_name, last_name, other_names?, pin, class_id?, session_id? },
//     link_student_ids?: string[] }                        // parent
// action "reset_password": { action:"reset_password", school_id, user_id, new_password }
//
// Authorization: platform admin, or an ACTIVE school_admin of school_id.
// Only a platform admin may create a school_admin.
import { adminClient, corsHeaders, fail, isActiveSchoolAdmin, isPlatformAdmin, json, requireCaller,
         studentEmail, UUID_RE } from "../_shared/lib.ts";

const ROLES = ["student", "teacher", "parent", "school_admin"];
const PIN_RE = /^[A-Za-z0-9]{6,32}$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail(405, "method_not_allowed", "Use POST.");

  const callerId = await requireCaller(req);
  if (!callerId) return fail(401, "unauthenticated", "Sign in first.");

  let b: Record<string, any>;
  try { b = await req.json(); } catch { return fail(400, "bad_request", "Invalid JSON."); }
  const schoolId = String(b.school_id ?? "");
  if (!UUID_RE.test(schoolId)) return fail(400, "bad_request", "school_id must be a UUID.");

  const admin = adminClient();
  const platform = await isPlatformAdmin(admin, callerId);
  if (!platform && !(await isActiveSchoolAdmin(admin, callerId, schoolId))) {
    return fail(403, "forbidden", "Only an administrator of this school may do this.");
  }
  const { data: school } = await admin.from("schools").select("id, school_code, is_active").eq("id", schoolId).maybeSingle();
  if (!school || !school.is_active) return fail(404, "not_found", "School not found or inactive.");

  const audit = (action: string, entityId: string | null, metadata: Record<string, unknown>) =>
    admin.from("audit_logs").insert({
      school_id: schoolId, actor_id: callerId, actor_role: platform ? "platform_admin" : "school_admin",
      action, entity_type: "account", entity_id: entityId, metadata,
    });

  // ------------------------------------------------------------------ reset_password
  if (b.action === "reset_password") {
    const userId = String(b.user_id ?? ""); const pw = String(b.new_password ?? "");
    if (!UUID_RE.test(userId)) return fail(400, "bad_request", "user_id must be a UUID.");
    const { data: m } = await admin.from("school_members").select("role").eq("school_id", schoolId).eq("user_id", userId).maybeSingle();
    if (!m) return fail(404, "not_found", "User is not a member of this school.");
    if (m.role === "school_admin" && !platform) return fail(403, "forbidden", "Only the platform can reset an administrator.");
    const ok = m.role === "student" ? PIN_RE.test(pw) : pw.length >= 10;
    if (!ok) return fail(400, "weak_password", m.role === "student" ? "PIN must be 6-32 letters/digits." : "Password must be at least 10 characters.");
    const { error } = await admin.auth.admin.updateUserById(userId, { password: pw });
    if (error) return fail(500, "internal", "Could not update the password.");
    await audit("account.password_reset", userId, { role: m.role });
    return json({ user_id: userId });
  }

  if (b.action !== "create") return fail(400, "bad_request", "Unknown action.");

  // ------------------------------------------------------------------ create
  const role = String(b.role ?? "");
  if (!ROLES.includes(role)) return fail(400, "bad_request", "Invalid role.");
  if (role === "school_admin" && !platform) return fail(403, "forbidden", "Only the platform can create school administrators.");

  let email: string; let password: string; let fullName = String(b.full_name ?? "").trim();
  const st = b.student ?? {};
  if (role === "student") {
    const adm = String(st.admission_number ?? "").trim();
    if (!adm || adm.length > 40 || !String(st.first_name ?? "").trim() || !String(st.last_name ?? "").trim()) {
      return fail(400, "bad_request", "student.admission_number, first_name and last_name are required.");
    }
    if (!PIN_RE.test(String(st.pin ?? ""))) return fail(400, "weak_password", "PIN must be 6-32 letters/digits.");
    email = studentEmail(school.school_code, adm); password = String(st.pin);
    fullName = fullName || `${st.first_name} ${st.last_name}`.trim();
  } else {
    email = String(b.email ?? "").trim().toLowerCase(); password = String(b.password ?? "");
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return fail(400, "bad_request", "A valid email is required.");
    if (password.length < 10) return fail(400, "weak_password", "Password must be at least 10 characters.");
  }

  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email, password, email_confirm: true, user_metadata: { full_name: fullName },
  });
  if (createErr || !created.user) {
    const dup = /already|exists|registered/i.test(createErr?.message ?? "");
    return fail(dup ? 409 : 500, dup ? "already_exists" : "internal", dup ? "This account already exists." : "Could not create the account.");
  }
  const userId = created.user.id;
  // No trigger exists on auth.users (shared project), so the profile row is created here.
  const { error: pErr } = await admin.from("profiles").insert({ id: userId, full_name: fullName || null });
  if (pErr) { await admin.auth.admin.deleteUser(userId); return fail(500, "internal", "Could not create the profile."); }
  let studentId: string | null = null;

  const rollback = async () => {                       // best-effort cleanup, order matters (FK restrict)
    if (studentId) {
      await admin.from("enrollments").delete().eq("student_id", studentId);
      await admin.from("students").delete().eq("id", studentId);
    }
    await admin.from("school_members").delete().eq("school_id", schoolId).eq("user_id", userId);
    await admin.auth.admin.deleteUser(userId);
  };

  const { error: mErr } = await admin.from("school_members").insert({
    school_id: schoolId, user_id: userId, role,
    staff_number: b.staff_number ?? null, job_title: b.job_title ?? null,
  });
  if (mErr) { await rollback(); return fail(400, "bad_request", "Could not add the user to the school."); }

  if (role === "student") {
    const { data: s, error: sErr } = await admin.from("students").insert({
      school_id: schoolId, user_id: userId, admission_number: String(st.admission_number).trim(),
      first_name: String(st.first_name).trim(), last_name: String(st.last_name).trim(),
      other_names: st.other_names ?? null,
    }).select("id").single();
    if (sErr || !s) { await rollback(); return fail(409, "already_exists", "A student with this admission number already exists."); }
    studentId = s.id;
    if (st.class_id && st.session_id) {
      const { error: eErr } = await admin.from("enrollments").insert({
        school_id: schoolId, student_id: studentId, class_id: st.class_id, session_id: st.session_id,
      });
      if (eErr) { await rollback(); return fail(400, "bad_request", "class_id/session_id do not belong to this school."); }
    }
  }

  if (role === "parent" && Array.isArray(b.link_student_ids) && b.link_student_ids.length) {
    const rows = b.link_student_ids.map((id: string) => ({ school_id: schoolId, parent_user_id: userId, student_id: id }));
    const { error: lErr } = await admin.from("parent_students").insert(rows);
    if (lErr) { await rollback(); return fail(400, "bad_request", "One or more students are not in this school."); }
  }

  await audit("account.provisioned", userId, { role, student_id: studentId });
  return json({ user_id: userId, student_id: studentId, role }, 201);
});
