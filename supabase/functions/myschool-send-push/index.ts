// POST /functions/v1/myschool-send-push
// Called by a Supabase Database Webhook on myschool.notifications (INSERT and UPDATE).
// Sends the notification to the user's registered phones through Firebase Cloud Messaging (HTTP v1).
//
// Secrets (Edge Functions > Secrets):  PUSH_WEBHOOK_SECRET  and  FCM_SERVICE_ACCOUNT (the whole service-account JSON).
// Verify JWT: OFF (the webhook sends the shared secret in the x-webhook-secret header instead).
import { adminClient, corsHeaders, fail, json } from "../_shared/lib.ts";

const WEBHOOK_SECRET = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
let account: { client_email: string; private_key: string; project_id: string; token_uri?: string } | null = null;
try { account = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? ""); } catch { account = null; }

let cached: { token: string; expires: number } | null = null;

function b64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function accessToken(): Promise<string> {
  if (!account) throw new Error("FCM_SERVICE_ACCOUNT is missing or invalid");
  if (cached && cached.expires > Date.now() + 60_000) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const tokenUri = account.token_uri ?? "https://oauth2.googleapis.com/token";
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: account.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri, iat: now, exp: now + 3600,
  }));
  const pem = account.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const assertion = `${header}.${claims}.${b64url(sig)}`;
  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) throw new Error("Could not get a Google access token");
  cached = { token: data.access_token, expires: Date.now() + (data.expires_in ?? 3600) * 1000 };
  return cached.token;
}

type Notification = { school_id?: string; user_id: string; kind?: string; title: string; body?: string | null; entity_id?: string | null; read_at?: string | null };

async function sendOne(token: string, n: Notification): Promise<"ok" | "dead" | "error"> {
  const access = await accessToken();
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${account!.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token,
        notification: { title: n.title, body: n.body ?? "" },
        data: { kind: String(n.kind ?? ""), entity_id: String(n.entity_id ?? ""), school_id: String(n.school_id ?? "") },
        android: { priority: "HIGH" },
      },
    }),
  });
  if (res.ok) return "ok";
  const err = await res.json().catch(() => ({}));
  const status = err?.error?.status ?? "";
  return (res.status === 404 || status === "NOT_FOUND" || status === "UNREGISTERED") ? "dead" : "error";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail(405, "method_not_allowed", "Use POST.");
  if (!WEBHOOK_SECRET || !safeEqual(req.headers.get("x-webhook-secret") ?? "", WEBHOOK_SECRET)) {
    return fail(401, "unauthorized", "Not allowed.");
  }
  if (!account) return fail(500, "not_configured", "Push is not configured yet.");

  let payload: { type?: string; record?: Notification; old_record?: Notification };
  try { payload = await req.json(); } catch { return fail(400, "bad_request", "Invalid JSON."); }
  const n = payload.record;
  if (!n || !n.user_id || !n.title || n.read_at) return json({ skipped: "nothing to send" });
  // An UPDATE only matters when the same unread notification got new text (e.g. a meeting was cancelled).
  if (payload.type === "UPDATE" && payload.old_record?.title === n.title) return json({ skipped: "no change" });

  const admin = adminClient();
  const { data: tokens } = await admin.from("device_tokens").select("id, token").eq("user_id", n.user_id);
  let sent = 0, removed = 0;
  for (const t of tokens ?? []) {
    try {
      const r = await sendOne(t.token as string, n);
      if (r === "ok") sent++;
      if (r === "dead") {
        await admin.from("device_tokens").delete().eq("id", t.id);
        removed++;
      }
    } catch (_) { /* one failing phone must not stop the others */ }
  }
  return json({ sent, removed });
});
