#!/usr/bin/env bash
set -euo pipefail

REQUIRED_M365_VERSION="11.10.0"
MIN_NODE_MAJOR=20
FAILURES=0

usage() {
  cat <<'EOF'
Usage:
  check-m365-prerequisites.sh

Checks the local workstation tools required for the Microsoft 365 delegated
integration track. This script does not install anything.

Required tools:
  bash, git, node 20+, npm, jq, az, and m365 11.10.0.
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

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

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

if [[ "$FAILURES" -gt 0 ]]; then
  cat <<'EOF'

One or more prerequisites are missing or use an unsupported version.
Use the installation section in README.md, then close and reopen the terminal
and run this checker again.
EOF
  exit 1
fi

cat <<'EOF'

All Microsoft 365 delegated integration prerequisites are available.
Next step:
  az login --tenant <MICROSOFT_TENANT_ID> --allow-no-subscriptions
EOF
