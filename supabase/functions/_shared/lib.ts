// Shared helpers for MySchool Edge Functions (Deno). The service-role key is read from the
// environment that Supabase injects into Edge Functions; it must never be sent to a client.
import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function fail(status: number, code: string, message: string): Response {
  return json({ error: { code, message } }, status);
}

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function required(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing environment variable ${name}`);
  return v;
}

/** Service-role client: bypasses RLS. Server-side use only. */
export function adminClient(): SupabaseClient {
  return createClient(required("SUPABASE_URL"), required("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
    db: { schema: "myschool" },   // all MySchool tables live in the myschool schema
  });
}

export function anonClient(): SupabaseClient {
  return createClient(required("SUPABASE_URL"), required("SUPABASE_ANON_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Lower-case, letters/digits only, other runs collapsed to '-'. */
export function normalizeKey(value: string): string {
  return value.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

/** Deterministic internal login identity for a student. Never shown to users. */
export function studentEmail(schoolCode: string, admissionNumber: string): string {
  const domain = Deno.env.get("STUDENT_EMAIL_DOMAIN") ?? "students.myschool.local";
  return `${normalizeKey(admissionNumber)}.${normalizeKey(schoolCode)}@${domain}`;
}

/** Verifies the caller's JWT and returns their user id. */
export async function requireCaller(req: Request): Promise<string | null> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const { data, error } = await anonClient().auth.getUser(token);
  return error || !data.user ? null : data.user.id;
}

export async function isPlatformAdmin(admin: SupabaseClient, userId: string): Promise<boolean> {
  const { data } = await admin.from("profiles").select("is_platform_admin").eq("id", userId).maybeSingle();
  return data?.is_platform_admin === true;
}

export async function isActiveSchoolAdmin(admin: SupabaseClient, userId: string, schoolId: string): Promise<boolean> {
  const { data } = await admin.from("school_members").select("id")
    .eq("school_id", schoolId).eq("user_id", userId).eq("role", "school_admin").eq("status", "active").maybeSingle();
  return !!data;
}
