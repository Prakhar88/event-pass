#!/usr/bin/env bash
# One-command deploy: hosting (Amplify) -> backend (API) -> build & upload all three frontends.
# Usage: SENDER_EMAIL=you@example.com [TELEGRAM_BOT_TOKEN=...] [TELEGRAM_BOT_USERNAME=...] ./deploy-all.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
REGION=${AWS_REGION:-ap-south-1}
BACKEND_STACK=${STACK:-event-ticketing}
FRONTEND_STACK=${FRONTEND_STACK:-event-ticketing-frontend}
FLUTTER=${FLUTTER:-flutter}
: "${SENDER_EMAIL:?Set SENDER_EMAIL to an SES-verified address}"

out() { aws cloudformation describe-stacks --stack-name "$1" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text; }

echo "==> 1/4 Hosting stack (Amplify Hosting)"
aws cloudformation deploy --template-file "$ROOT/frontend/infra/hosting.yaml" \
  --stack-name "$FRONTEND_STACK" --region "$REGION" --no-fail-on-empty-changeset

ATTENDEE_URL=$(out "$FRONTEND_STACK" AttendeeUrl)

echo "==> 2/4 Backend stack (ticket emails link to $ATTENDEE_URL)"
FRONTEND_BASE_URL="$ATTENDEE_URL" "$ROOT/backend/deploy.sh"

API_URL=$(out "$BACKEND_STACK" ApiUrl)
GATE_KEY=$(aws apigateway get-api-key --api-key "$(out "$BACKEND_STACK" GateApiKeyId)" \
  --include-value --query value --output text --region "$REGION")

echo "==> 3/4 Build frontends against $API_URL"
for app in admin-web attendee-web; do
  (cd "$ROOT/frontend/$app" && npm install --silent && VITE_API_BASE_URL="$API_URL" npx vite build --logLevel warn)
done
# NOTE: the gate key ends up in the public JS bundle. Fine for a demo; production should
# put /verify behind a server-side proxy or staff login (see frontend/README.md).
(cd "$ROOT/frontend/gate-app" && "$FLUTTER" build web --release \
  --dart-define=API_BASE_URL="$API_URL" --dart-define=GATE_API_KEY="$GATE_KEY")

echo "==> 4/4 Publish to Amplify Hosting"
APP_ID=$(out "$FRONTEND_STACK" AppId)
upload() { # <dist dir> <output prefix>
  local branch zip job url
  branch=$(out "$FRONTEND_STACK" "${2}Branch")
  zip=$(mktemp --suffix=.zip) && rm "$zip"
  (cd "$1" && zip -qr "$zip" .)
  read -r job url < <(aws amplify create-deployment --app-id "$APP_ID" --branch-name "$branch" \
    --region "$REGION" --query '[jobId,zipUploadUrl]' --output text)
  curl -sf -X PUT -H 'Content-Type: application/zip' --upload-file "$zip" "$url"
  aws amplify start-deployment --app-id "$APP_ID" --branch-name "$branch" --job-id "$job" \
    --region "$REGION" --query 'jobSummary.status' --output text
  rm -f "$zip"
}
upload "$ROOT/frontend/admin-web/dist"    Admin
upload "$ROOT/frontend/attendee-web/dist" Attendee
upload "$ROOT/frontend/gate-app/build/web" Gate

echo
echo "API:       $API_URL"
echo "Admin:     $(out "$FRONTEND_STACK" AdminUrl)"
echo "Attendee:  $ATTENDEE_URL"
echo "Gate:      $(out "$FRONTEND_STACK" GateUrl)"
