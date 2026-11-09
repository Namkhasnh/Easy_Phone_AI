#!/bin/sh
# Check 0001_init.sql on a throwaway Postgres in Docker (no Supabase). Usage: sh backend/migrations/checks/run_local.sh
set -eu
DIR="$(cd "$(dirname "$0")/.." && pwd)"
NAME="easyphone-migration-check-$$"
docker run -d --rm --name "$NAME" -e POSTGRES_PASSWORD=check -v "$DIR:/m:ro" postgres:16 >/dev/null
trap 'docker stop "$NAME" >/dev/null' EXIT
until docker exec "$NAME" pg_isready -U postgres -q; do sleep 1; done
sleep 1
for f in checks/supabase_stub.sql 0001_init.sql checks/0001_check.sql; do
  docker exec "$NAME" psql -q -U postgres -v ON_ERROR_STOP=1 -f "/m/$f"
done
