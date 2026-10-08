# MySchool Platform – Backend (Part 1)

Multi-tenant school platform: many schools, one Supabase backend. First feature: **digital student
results** with a draft → submitted → approved → published workflow. Consumed by a Flutter app and a
future web app / teacher & admin dashboards.

| Layer | Tech |
|---|---|
| Database | PostgreSQL (Supabase) – normalized schema, composite FKs, RLS |
| Auth | Supabase Auth (+ `student-login` Edge Function for admission-number/PIN login) |
| Server logic | SQL functions (workflow RPCs, search) + Edge Functions (account provisioning) |
| Files | Supabase Storage (public logos, private photos/scans) |

## Status – read this first
Written but **not yet executed**: the SQL migrations, pgTAP tests and Edge Functions were authored
without access to a Postgres/Supabase runtime. Run `scripts/test.sh` (needs Docker) before relying on
them and fix anything it reports. **AI/OCR scanning is not implemented**; only its database hooks
(`script_scans`, `result_items.source/scan_id`, the `script-scans` bucket) exist.

## Layout
```
docs/                 architecture.md  database.md  api.md (Flutter contract)  security.md
supabase/
  config.toml
  migrations/         0001 types · 0002 tenancy · 0003 people+academics · 0004 results ·
                      0005 announcements+audit · 0006 helpers/triggers/RPCs · 0007 RLS ·
                      0008 grants · 0009 storage
  functions/          student-login · provision-user · _shared
  tests/database/     pgTAP security suite
  seed.sql            LOCAL demo data only
scripts/test.sh       reset DB + run tests
.env.example
```

## Quick start (desktop/CI with Docker)
```bash
npm i -g supabase            # or see Supabase CLI docs
supabase start
supabase db reset            # applies migrations + seed.sql
supabase test db             # security tests
supabase functions serve --env-file ./supabase/functions/.env   # optional, for Edge Functions
```
Deploy: `supabase link --project-ref <ref>`, `supabase db push`, `supabase functions deploy`.
**Never run `seed.sql` in production.** Create the first platform admin by hand (see docs/security.md).
