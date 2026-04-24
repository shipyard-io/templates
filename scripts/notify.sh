#!/bin/bash
set -e

# Usage: bash scripts/notify.sh <app-name> <status> <commit-message> <actor> <sha> <ref_name> <repository> <run_id> <app-domain>

APP_NAME=$1
STATUS=$2
COMMIT_MSG=$3
ACTOR=$4
SHA=$5
REF_NAME=$6
REPOSITORY=$7
RUN_ID=$8
APP_DOMAIN=$9

case "$STATUS" in
  success)
    STATUS_LABEL="Deployed successfully"
    ICON="✅"
    ;;
  failure)
    STATUS_LABEL="Deploy failed"
    ICON="❌"
    ;;
  cancelled)
    STATUS_LABEL="Deploy cancelled"
    ICON="⚠️"
    ;;
  *)
    STATUS_LABEL="Deploy status unknown"
    ICON="🚀"
    ;;
esac

SHORT_SHA=$(echo "$SHA" | cut -c1-7)
SHORT_COMMIT=$(echo "$COMMIT_MSG" | head -n 1)

MESSAGE="
━━━━━━━━━━━━━━━━━━━━━━━━
${ICON} *${APP_NAME}*
━━━━━━━━━━━━━━━━━━━━━━━━

📌 *Status:* \`${STATUS_LABEL}\`
🌿 *Branch:* \`${REF_NAME}\`
👤 *Actor:* \`${ACTOR}\`

💬 *Commit:*
\`${SHORT_COMMIT}\`

🔖 *SHA:* \`${SHORT_SHA}\`

$( [ -n "$APP_DOMAIN" ] && echo "🔗 *Domain:* [${APP_DOMAIN}](https://${APP_DOMAIN})" )

━━━━━━━━━━━━━━━━━━━━━━━━
🔎 [View Workflow Run](https://github.com/${REPOSITORY}/actions/runs/${RUN_ID})
"

# Remove leading whitespaces for clean Markdown formatting
MESSAGE=$(echo "$MESSAGE" | sed 's/^[ \t]*//')

curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${MESSAGE}" \
  --data-urlencode "parse_mode=Markdown" \
  --data-urlencode "disable_web_page_preview=true"

echo "Telegram card sent."
