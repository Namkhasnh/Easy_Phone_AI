#!/bin/sh
# Deploy the backend to Google Cloud Run (D-315). Usage (from backend/): sh deploy/cloudrun.sh <PROJECT_ID>
# Secrets: read from backend/.env into a temporary env-vars file outside the repo, deleted afterwards (never in git).
set -eu
PROJECT="${1:?usage: sh deploy/cloudrun.sh <PROJECT_ID>}"
REGION="asia-southeast1"
SERVICE="easyphone-backend"
cd "$(dirname "$0")/.."

TMP="$(mktemp -t easyphone-env).yaml"
trap 'rm -f "$TMP"' EXIT
python3 - "$TMP" <<'PY'
import sys
out = []
for line in open(".env", encoding="utf-8"):
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    if key in ("PORT", "ENV"):
        continue
    out.append(f'{key}: "{value.strip().strip(chr(34))}"')
try:
    pin = open("certs/xcode_storekit_leaf.sha256", encoding="utf-8").read().strip()
    out.append(f'XCODE_STOREKIT_LEAF_SHA256: "{pin}"')     # Cloud Run has no lasting disk (D-315)
except FileNotFoundError:
    pass
out.append('ENV: "cloudrun"')
open(sys.argv[1], "w", encoding="utf-8").write("\n".join(out) + "\n")
PY

gcloud run deploy "$SERVICE" --project "$PROJECT" --region "$REGION" --source . \
  --allow-unauthenticated --min-instances 0 --max-instances 2 --memory 512Mi --cpu 1 --timeout 30 \
  --env-vars-file "$TMP" --quiet
gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format 'value(status.url)'
