#!/usr/bin/env bash
# End-to-end demo against the deployed stack.
# Usage: ADMIN_EMAIL=... ADMIN_PASSWORD=... ATTENDEE_EMAIL=... ./demo.sh
set -euo pipefail
STACK=${STACK:-event-ticketing}
REGION=${AWS_REGION:-ap-south-1}
out() { aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
json() { python3 -c "import sys,json; print(json.load(sys.stdin)$1)"; }

API=$(out ApiUrl)
GATE_KEY=$(aws apigateway get-api-key --api-key "$(out GateApiKeyId)" --include-value --query value --output text --region "$REGION")
TICKETS_TABLE=$(aws cloudformation describe-stack-resource --stack-name "$STACK" --region "$REGION" --logical-resource-id TicketsTable --query StackResourceDetail.PhysicalResourceId --output text)

echo "== register admin (only works for the first admin)"
curl -s -X POST "$API/auth/admin/register" -H 'Content-Type: application/json' \
  -d "{\"name\":\"Admin\",\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}"; echo

TOKEN=$(curl -s -X POST "$API/auth/admin/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" | json '["token"]')

echo "== create event"
EV=$(curl -s -X POST "$API/admin/events" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"CAD Tech Fest 2026","venue":"VIT Anna Auditorium","date":"2026-10-25T18:00:00+05:30","capacity":100}')
echo "$EV"
EID=$(echo "$EV" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("eventId") or d["event"]["eventId"])')

echo "== issue ticket (email + .ics + Telegram link)"
T=$(curl -s -X POST "$API/events/$EID/tickets" -H 'Content-Type: application/json' \
  -d "{\"attendeeName\":\"Demo Attendee\",\"attendeeEmail\":\"$ATTENDEE_EMAIL\"}")
echo "$T"
TID=$(echo "$T" | json '["ticketId"]')

QR=$(aws dynamodb get-item --region "$REGION" --table-name "$TICKETS_TABLE" \
  --key "{\"ticketId\":{\"S\":\"$TID\"}}" --query 'Item.qrToken.S' --output text)

verify() { curl -s -X POST "$API/verify" -H "x-api-key: $GATE_KEY" -H 'Content-Type: application/json' -d "{\"token\":\"$1\",\"gateId\":\"$2\"}"; echo; }
echo "== scan 1 (expect valid)";          verify "$QR" gate-1
echo "== scan 2 (expect already_used)";   verify "$QR" gate-2
echo "== tampered (expect invalid_token)"; verify "${QR}x" gate-1
echo "== no gate key (expect 403)"
curl -s -o /dev/null -w "%{http_code}\n" -X POST "$API/verify" -d '{}'
echo "== stats"
curl -s "$API/admin/events/$EID/stats" -H "Authorization: Bearer $TOKEN"; echo
