#!/usr/bin/env bash
# Deploy without SAM CLI: `aws cloudformation package` uploads src/ and resolves the SAM transform.
# Usage: SENDER_EMAIL=you@example.com [TELEGRAM_BOT_TOKEN=123:ABC] [TELEGRAM_BOT_USERNAME=my_bot] ./deploy.sh
set -euo pipefail
cd "$(dirname "$0")"

: "${SENDER_EMAIL:?Set SENDER_EMAIL to an SES-verified address}"
STACK=${STACK:-event-ticketing}
REGION=${AWS_REGION:-ap-south-1}
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ARTIFACTS="event-ticketing-artifacts-${ACCOUNT}-${REGION}"

# Ticket emails link to the hosted attendee site when the frontend stack exists
if [ -z "${FRONTEND_BASE_URL:-}" ]; then
  FRONTEND_BASE_URL=$(aws cloudformation describe-stacks --stack-name event-ticketing-frontend --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AttendeeUrl'].OutputValue" --output text 2>/dev/null || true)
fi

aws s3api head-bucket --bucket "$ARTIFACTS" 2>/dev/null || \
  aws s3 mb "s3://$ARTIFACTS" --region "$REGION"

npm install --prefix src --omit=dev --silent

aws cloudformation package \
  --template-file template.yaml \
  --s3-bucket "$ARTIFACTS" \
  --output-template-file packaged.yaml \
  --region "$REGION"

aws cloudformation deploy \
  --template-file packaged.yaml \
  --stack-name "$STACK" \
  --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
  --region "$REGION" \
  --parameter-overrides \
    SenderEmail="$SENDER_EMAIL" \
    TelegramBotToken="${TELEGRAM_BOT_TOKEN:-}" \
    TelegramBotUsername="${TELEGRAM_BOT_USERNAME:-}" \
    FrontendBaseUrl="${FRONTEND_BASE_URL:-http://localhost:5174}"

aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query 'Stacks[0].Outputs' --output table

# Point the Telegram bot at the webhook (secret = same derivation as lib/telegram.js)
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
  API_URL=$(aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text)
  SECRET=$(printf '%s' "$TELEGRAM_BOT_TOKEN" | sha256sum | cut -c1-48)
  curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
    --data-urlencode "url=${API_URL}/telegram/webhook" \
    --data-urlencode "secret_token=${SECRET}" \
    --data-urlencode 'allowed_updates=["message"]'
  echo
fi
