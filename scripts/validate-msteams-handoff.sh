#!/usr/bin/env bash
#
# Offline validation for the contract produced by provision-aria-msteams-bot.sh.
#
set -euo pipefail

RSC_PERMISSIONS=(
  "ChannelMessage.Read.Group"
  "ChannelMessage.Send.Group"
  "Member.Read.Group"
  "Owner.Read.Group"
  "ChannelSettings.Read.Group"
  "TeamMember.Read.Group"
  "TeamSettings.Read.Group"
  "ChatMessage.Read.Chat"
)

usage() {
  cat <<'EOF'
Usage:
  validate-msteams-handoff.sh <aria-msteams-handoff.json> [aria-msteams-secret.json]

The second file is optional. When provided, this script validates that it
contains the four MSTEAMS_* keys and that app/tenant values match the public
handoff. Secret values are never printed.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

[[ "${1:-}" != "-h" && "${1:-}" != "--help" ]] || {
  usage
  exit 0
}
[[ $# -ge 1 && $# -le 2 ]] || {
  usage >&2
  exit 1
}

for cmd in jq unzip awk; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
done

PUBLIC_FILE="$1"
SECRET_FILE="${2:-}"
[[ -f "$PUBLIC_FILE" ]] || die "file does not exist: $PUBLIC_FILE"
BASE_DIR="$(cd "$(dirname "$PUBLIC_FILE")" && pwd)"

jq -e '
  def uuid:
    type == "string"
    and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");
  . as $handoff
  | .schemaVersion == 1
    and .integration == "aria-openclaw-msteams"
    and (.microsoft.tenantId | uuid)
    and (.microsoft.teamsAppId | uuid)
    and (.microsoft.botAppId | uuid)
    and .microsoft.signInAudience == "AzureADMyOrg"
    and .microsoft.botLocation == "teams-managed"
    and (.permissions.tenantWideGraphApplication | length == 0)
    and .doctorClassification.nonSsoFailures == 0
    and .doctorClassification.ssoRequiredByAria == false
    and (.aria.tenantId | test("^[a-z0-9][a-z0-9-]{0,62}$"))
    and (
      ($handoff.aria.endpointMode // "aria") as $endpointMode
      | if $endpointMode == "aria" then
          (.aria.messagingEndpoint
            | startswith("https://")
              and endswith("/teams/" + $handoff.aria.tenantId + "/api/messages"))
        elif $endpointMode == "test" then
          (.aria.messagingEndpoint
            | startswith("https://") and endswith("/api/messages"))
        else
          false
        end
    )
' "$PUBLIC_FILE" >/dev/null || die "invalid public handoff"

BOT_APP_ID="$(jq -r '.microsoft.botAppId' "$PUBLIC_FILE")"
MICROSOFT_TENANT_ID="$(jq -r '.microsoft.tenantId' "$PUBLIC_FILE")"
PACKAGE_NAME="$(jq -r '.artifacts.appPackage' "$PUBLIC_FILE")"
EXPECTED_SHA256="$(jq -r '.artifacts.appPackageSha256' "$PUBLIC_FILE")"
PACKAGE_FILE="$BASE_DIR/$PACKAGE_NAME"
[[ -f "$PACKAGE_FILE" ]] || die "package does not exist: $PACKAGE_FILE"

PACKAGE_ENTRIES="$(unzip -Z1 "$PACKAGE_FILE")"
for required_entry in manifest.json color.png outline.png; do
  awk -v wanted="$required_entry" '$0 == wanted { found = 1 } END { exit !found }' \
    <<<"$PACKAGE_ENTRIES" ||
    die "package does not contain $required_entry at the root"
done

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA256="$(sha256sum "$PACKAGE_FILE" | awk '{print $1}')"
else
  command -v shasum >/dev/null 2>&1 || die "missing sha256sum or shasum"
  ACTUAL_SHA256="$(shasum -a 256 "$PACKAGE_FILE" | awk '{print $1}')"
fi
[[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]] || die "package SHA-256 does not match"

PACKAGE_MANIFEST="$(unzip -p "$PACKAGE_FILE" manifest.json)"
EXPECTED_RSC_JSON="$(printf '%s\n' "${RSC_PERMISSIONS[@]}" | jq -R . | jq -s .)"
jq -e \
  --arg botId "$BOT_APP_ID" \
  --argjson expectedRsc "$EXPECTED_RSC_JSON" '
    [
      .authorization.permissions.resourceSpecific[]?
      | select(.type == "Application")
      | .name
    ] as $actualRsc
    | ([.bots[]? | select(
        .botId == $botId
        and .supportsFiles == true
        and ((["personal", "team", "groupChat"] - .scopes) | length == 0)
      )] | length == 1)
      and (.webApplicationInfo.id == $botId)
      and (($expectedRsc - $actualRsc) | length == 0)
      and (($actualRsc - $expectedRsc) | length == 0)
      and ((.authorization.permissions.resourceSpecific | length) == ($expectedRsc | length))
  ' <<<"$PACKAGE_MANIFEST" >/dev/null || die "invalid package manifest"

if [[ -n "$SECRET_FILE" ]]; then
  [[ -f "$SECRET_FILE" ]] || die "file does not exist: $SECRET_FILE"
  jq -e '
    def uuid:
      type == "string"
      and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");
    (.MSTEAMS_APP_ID | uuid)
    and (.MSTEAMS_APP_PASSWORD | type == "string" and length > 0)
    and (.MSTEAMS_TENANT_ID | uuid)
    and .MSTEAMS_AUTH_TYPE == "secret"
  ' "$SECRET_FILE" >/dev/null || die "invalid secret handoff"

  SECRET_APP_ID="$(jq -r '.MSTEAMS_APP_ID' "$SECRET_FILE")"
  SECRET_TENANT_ID="$(jq -r '.MSTEAMS_TENANT_ID' "$SECRET_FILE")"
  [[ "$(lower "$SECRET_APP_ID")" == "$(lower "$BOT_APP_ID")" ]] ||
    die "public and secret App IDs do not match"
  [[ "$(lower "$SECRET_TENANT_ID")" == "$(lower "$MICROSOFT_TENANT_ID")" ]] ||
    die "public and secret Tenant IDs do not match"
fi

echo "OK: Microsoft Teams handoff is valid"
echo "    Bot App ID: $BOT_APP_ID"
echo "    Tenant ID:  $MICROSOFT_TENANT_ID"
echo "    Package:    $PACKAGE_FILE"
