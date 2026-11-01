// POST /functions/v1/myschool-student-login   (no JWT required)
// { "school_code": "CHR-ADO", "admission_number": "2024/017", "pin": "482913" }
// -> { session: { access_token, refresh_token, expires_in, expires_at, token_type }, student: {...} }
// Flutter then calls supabase.auth.setSession(refresh_token) and uses the normal Supabase client.
// After 5 wrong attempts for the same student within 15 minutes the student is locked out for the rest of that window.
import { adminClient, anonClient, corsHeaders, fail, json, normalizeKey, studentEmail } from "../_shared/lib.ts";

const BAD = "School ID, admission number or PIN is incorrect.";
const MAX_FAILS = 5;
const WINDOW_MINUTES = 15;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail(405, "method_not_allowed", "Use POST.");

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return fail(400, "bad_request", "Invalid JSON."); }

  const code = String(body.school_code ?? "").trim().toUpperCase();
  const admission = String(body.admission_number ?? "").trim();
  const pin = String(body.pin ?? "");
  if (code.length < 3 || code.length > 20 || admission.length < 1 || admission.length > 40 ||
      pin.length < 6 || pin.length > 72) {
    return fail(401, "invalid_credentials", BAD);       // same answer: no enumeration
  }

  const admin = adminClient();
  const key = `${normalizeKey(code)}|${normalizeKey(admission)}`;
  const since = new Date(Date.now() - WINDOW_MINUTES * 60 * 1000).toISOString();

  // Too many recent wrong attempts for this student? Refuse before even checking the PIN.
  const { count } = await admin.from("student_login_attempts")
    .select("id", { count: "exact", head: true }).eq("key", key).eq("ok", false).gte("at", since);
  if ((count ?? 0) >= MAX_FAILS) {
    return fail(429, "too_many_attempts",
      `Too many wrong attempts. Please wait ${WINDOW_MINUTES} minutes, or ask your school to reset your PIN.`);
  }

  const client = anonClient();
  const { data, error } = await client.auth.signInWithPassword({
    email: studentEmail(code, admission), password: pin,
  });
  if (error || !data.session || !data.user) {
    await admin.from("student_login_attempts").insert({ key, ok: false });
    return fail(401, "invalid_credentials", BAD);
  }

  // Password is right: make sure this really is an active student of an active school with that code.
  const { data: school } = await admin.from("schools").select("id, school_code, is_active")
    .eq("school_code", code).maybeSingle();
  const { data: student } = school ? await admin.from("students")
    .select("id, school_id, admission_number, first_name, last_name, status")
    .eq("user_id", data.user.id).eq("school_id", school.id).maybeSingle() : { data: null };
  const { data: member } = school ? await admin.from("school_members").select("status")
    .eq("school_id", school.id).eq("user_id", data.user.id).eq("role", "student").maybeSingle() : { data: null };

  if (!school || !student || !member) return fail(401, "invalid_credentials", BAD);
  if (!school.is_active || member.status !== "active" || student.status === "suspended" ||
      student.status === "withdrawn" || student.status === "transferred") {
    return fail(403, "account_disabled", "This account is not active. Contact your school.");
  }

  // Success: forget the earlier wrong attempts, and tidy old rows now and then.
  await admin.from("student_login_attempts").delete().eq("key", key);
  if (Math.random() < 0.05) {
    await admin.from("student_login_attempts").delete().lt("at", new Date(Date.now() - 24 * 3600 * 1000).toISOString());
  }

  const s = data.session;
  return json({
    session: { access_token: s.access_token, refresh_token: s.refresh_token, expires_in: s.expires_in,
               expires_at: s.expires_at, token_type: s.token_type },
    student: { id: student.id, school_id: student.school_id, school_code: school.school_code,
               admission_number: student.admission_number, first_name: student.first_name, last_name: student.last_name },
  });
});
