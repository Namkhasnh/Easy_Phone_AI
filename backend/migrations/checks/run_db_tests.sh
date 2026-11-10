#!/bin/sh
# Run the `db` pytest suite (repositories + /v1/me) on a throwaway Postgres in Docker with 0001_init.sql applied.
# Usage (from backend/): sh migrations/checks/run_db_tests.sh
set -eu
DIR="$(cd "$(dirname "$0")/.." && pwd)"
NAME="easyphone-db-tests-$$"
docker run -d --rm --name "$NAME" -e POSTGRES_PASSWORD=check -p 127.0.0.1::5432 -v "$DIR:/m:ro" postgres:16 >/dev/null
trap 'docker stop "$NAME" >/dev/null' EXIT
until docker exec "$NAME" pg_isready -U postgres -q; do sleep 1; done
sleep 1
for f in checks/supabase_stub.sql 0001_init.sql; do
  docker exec "$NAME" psql -q -U postgres -v ON_ERROR_STOP=1 -f "/m/$f"
done
PORT="$(docker port "$NAME" 5432/tcp | head -1 | sed 's/.*://')"
cd "$DIR/.."
TEST_DATABASE_URL="postgresql://postgres:check@127.0.0.1:$PORT/postgres" uv run pytest -q -m db
