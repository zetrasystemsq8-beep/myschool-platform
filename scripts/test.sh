#!/usr/bin/env bash
# Rebuild the local database from migrations + seed and run the pgTAP security suite.
# Requires: Supabase CLI + Docker (a desktop/CI machine; Termux cannot run Docker).
set -euo pipefail
cd "$(dirname "$0")/.."
supabase start
supabase db reset
supabase test db
