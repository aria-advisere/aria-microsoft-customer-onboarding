#!/usr/bin/env bash
set -euo pipefail
umask 077

SECRET_JSON=""
PORT="3978"

usage() {
  cat <<'EOF'
Usage:
  start-msteams-echo-bot.sh \
    --secret-json ./aria-example-microsoft/aria-msteams-secret.json \
    [--port 3978]

Starts the temporary Microsoft Teams SDK echo bot used for live onboarding
validation. The script reads the generated bot credentials without printing
them and listens on /api/messages.

Run npm ci in tools/teams-echo-bot before starting the bot.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --secret-json)
      [[ $# -ge 2 ]] || die "--secret-json requires a value"
      SECRET_JSON="$2"
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || die "--port requires a value"
      PORT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ -n "$SECRET_JSON" ]] || die "--secret-json is required"
[[ -f "$SECRET_JSON" ]] || die "secret JSON does not exist: $SECRET_JSON"
[[ "$PORT" =~ ^[0-9]+$ ]] || die "--port must be an integer"
(( PORT >= 1 && PORT <= 65535 )) || die "--port must be between 1 and 65535"

for command_name in node npm jq; do
  command -v "$command_name" >/dev/null 2>&1 ||
    die "missing required command: $command_name"
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ECHO_ROOT="$PACKAGE_ROOT/tools/teams-echo-bot"

[[ -d "$ECHO_ROOT/node_modules" ]] ||
  die "echo-bot dependencies are missing; run: cd tools/teams-echo-bot && npm ci"

CLIENT_ID="$(jq -er '.MSTEAMS_APP_ID | select(length > 0)' "$SECRET_JSON")" ||
  die "secret JSON is missing MSTEAMS_APP_ID"
CLIENT_SECRET="$(jq -er '.MSTEAMS_APP_PASSWORD | select(length > 0)' "$SECRET_JSON")" ||
  die "secret JSON is missing MSTEAMS_APP_PASSWORD"
TENANT_ID="$(jq -er '.MSTEAMS_TENANT_ID | select(length > 0)' "$SECRET_JSON")" ||
  die "secret JSON is missing MSTEAMS_TENANT_ID"

export CLIENT_ID CLIENT_SECRET TENANT_ID PORT

echo "Starting the temporary Teams SDK echo bot on port $PORT at /api/messages."
echo "Message text and credentials are not logged."
cd "$ECHO_ROOT"
exec npm start
