#!/usr/bin/env bash
set -euo pipefail

REQUIRED_M365_VERSION="11.10.0"
REQUIRED_TEAMS_VERSION="3.0.3"
MIN_NODE_MAJOR=20
FAILURES=0
TRACK="microsoft365"

usage() {
  cat <<'EOF'
Usage:
  check-m365-prerequisites.sh [--track microsoft365|teams|all]

Checks local workstation tools without installing anything. The default track
is microsoft365 for backward compatibility.

Common tools:
  bash, git, Node.js 20+, npm, and jq.

Microsoft 365 delegated integration:
  Azure CLI (az) and CLI for Microsoft 365 (m365) 11.10.0.

Microsoft Teams channel:
  unzip, Microsoft Teams CLI (teams) 3.0.3, and CLI for Microsoft 365 11.10.0.

An HTTPS tunnel is required only for the optional local echo-bot test. Use a
customer-approved tunnel such as ngrok; it is not required for production.
EOF
}

ok() {
  printf 'OK: %s\n' "$1"
}

missing() {
  printf 'MISSING: %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

wrong_version() {
  printf 'VERSION: %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --track)
      [[ $# -ge 2 ]] || {
        echo "Error: --track requires a value" >&2
        exit 1
      }
      TRACK="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      exit 1
      ;;
  esac
done

case "$TRACK" in
  microsoft365|teams|all) ;;
  *)
    echo "Error: --track must be microsoft365, teams, or all" >&2
    exit 1
    ;;
esac

if have_cmd bash; then
  ok "bash $(bash --version | head -n 1)"
else
  missing "bash"
fi

if have_cmd git; then
  ok "git $(git --version | awk '{print $3}')"
else
  missing "git"
fi

if have_cmd node; then
  NODE_VERSION="$(node --version | tr -d 'v')"
  NODE_MAJOR="${NODE_VERSION%%.*}"
  if [[ "$NODE_MAJOR" =~ ^[0-9]+$ && "$NODE_MAJOR" -ge "$MIN_NODE_MAJOR" ]]; then
    ok "node v$NODE_VERSION"
  else
    wrong_version "node v$NODE_VERSION found; Node.js $MIN_NODE_MAJOR+ is required"
  fi
else
  missing "node"
fi

if have_cmd npm; then
  ok "npm $(npm --version)"
else
  missing "npm"
fi

if have_cmd jq; then
  ok "jq $(jq --version)"
else
  missing "jq"
fi

if have_cmd m365; then
  M365_VERSION="$(
    m365 version --output text 2>/dev/null \
      | tr -d '\r' \
      | tail -n 1 \
      | tr -d '[:space:]v'
  )"
  if [[ "$M365_VERSION" == "$REQUIRED_M365_VERSION" ]]; then
    ok "CLI for Microsoft 365 $M365_VERSION"
  else
    wrong_version "CLI for Microsoft 365 $M365_VERSION found; $REQUIRED_M365_VERSION is required"
  fi
else
  missing "CLI for Microsoft 365 (m365)"
fi

if [[ "$TRACK" == "microsoft365" || "$TRACK" == "all" ]]; then
  if have_cmd az; then
    AZ_VERSION="$(az version --query '"azure-cli"' --output tsv 2>/dev/null || true)"
    if [[ -n "$AZ_VERSION" ]]; then
      ok "Azure CLI $AZ_VERSION"
    else
      ok "Azure CLI installed"
    fi
  else
    missing "Azure CLI (az)"
  fi

fi

if [[ "$TRACK" == "teams" || "$TRACK" == "all" ]]; then
  if have_cmd unzip; then
    ok "unzip installed"
  else
    missing "unzip"
  fi

  if have_cmd teams; then
    TEAMS_VERSION="$(teams --version 2>/dev/null | awk 'NR == 1 {print $1}')"
    if [[ "$TEAMS_VERSION" == "$REQUIRED_TEAMS_VERSION" ]]; then
      ok "Microsoft Teams CLI $TEAMS_VERSION"
    else
      wrong_version "Microsoft Teams CLI $TEAMS_VERSION found; $REQUIRED_TEAMS_VERSION is required"
    fi
  else
    missing "Microsoft Teams CLI (teams)"
  fi
fi

if [[ "$FAILURES" -gt 0 ]]; then
  cat <<'EOF'

One or more prerequisites are missing or use an unsupported version.
Use the installation section in README.md, then close and reopen the terminal
and run this checker again.
EOF
  exit 1
fi

case "$TRACK" in
  microsoft365)
    cat <<'EOF'

All Microsoft 365 delegated integration prerequisites are available.
Next step:
  az login --tenant <MICROSOFT_TENANT_ID> --allow-no-subscriptions
EOF
    ;;
  teams)
    cat <<'EOF'

All Microsoft Teams channel prerequisites are available.
Next step:
  teams login --device-code
  m365 login --authType deviceCode --appId <TEAMS_ONBOARDING_ADMIN_CLI_APP_ID> --tenant <MICROSOFT_TENANT_ID>
EOF
    ;;
  all)
    cat <<'EOF'

All Microsoft 365 and Microsoft Teams prerequisites are available.
EOF
    ;;
esac
