#!/usr/bin/env bash
#
# Customer-run onboarding for the ARIA/OpenClaw Microsoft Teams channel.
# Creates a single-tenant identity and Teams-managed bot, applies the OpenClaw
# RSC baseline, generates the app package, and separates public handoff data
# from secrets.
#
set -euo pipefail
umask 077

REQUIRED_TEAMS_CLI_VERSION="3.0.3"
TEAMS_BIN="${TEAMS_BIN:-teams}"
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

CUSTOMER_SLUG=""
ARIA_STAGE=""
ARIA_TENANT_ID=""
APP_NAME=""
ENDPOINT=""
EXPECTED_MICROSOFT_TENANT_ID=""
OUTPUT_DIR=""
DEVELOPER_NAME=""
WEBSITE_URL=""
PRIVACY_URL=""
TERMS_URL=""
COLOR_ICON=""
OUTLINE_ICON=""

usage() {
  cat <<'EOF'
Usage:
  provision-aria-msteams-bot.sh \
    --customer-slug contoso \
    --aria-stage staging \
    --aria-tenant-id contoso \
    --name "ARIA Contoso" \
    --endpoint "https://<aria-api>/teams/contoso/api/messages" \
    --microsoft-tenant-id 00000000-0000-0000-0000-000000000000 \
    --developer-name "ARIA" \
    --website-url "https://example.com" \
    --privacy-url "https://example.com/privacy" \
    --terms-url "https://example.com/terms" \
    --output-dir ./aria-contoso-microsoft

Required inputs:
  --customer-slug SLUG          Human-readable customer identifier.
  --aria-stage STAGE            ARIA stage that will receive the webhook.
  --aria-tenant-id ID           ARIA tenant/instance ID included in the endpoint.
  --name NAME                   Visible Teams app name, max 30 characters.
  --endpoint HTTPS_URL          Public ARIA endpoint ending in /api/messages.
  --microsoft-tenant-id UUID    Expected Microsoft tenant; prevents wrong-tenant setup.
  --developer-name NAME         Publisher/developer shown by Teams.
  --website-url HTTPS_URL       Publisher website.
  --privacy-url HTTPS_URL       Privacy policy.
  --terms-url HTTPS_URL         Terms of use.
  --output-dir PATH             Private output folder.

Optional inputs:
  --color-icon PATH             PNG 192x192.
  --outline-icon PATH           PNG 32x32.
  -h, --help                    Show this help.

Prerequisites:
  Node.js 20+, jq, unzip, and @microsoft/teams.cli 3.0.3.
  npm install -g @microsoft/teams.cli@3.0.3
  teams login

The script creates resources in the signed-in Microsoft tenant. It does not
automatically publish the app to the organizational catalog or install it in
teams. It returns the package and install link so the administrator controls
the installation scope.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

is_uuid() {
  [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

is_safe_slug() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]
}

is_https_url() {
  [[ "$1" =~ ^https://[^[:space:]]+$ ]]
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

env_value() {
  local key="$1"
  local file="$2"
  awk -v wanted="$key" '
    index($0, wanted "=") == 1 {
      sub(/^[^=]*=/, "")
      print
      exit
    }
  ' "$file"
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --customer-slug)
      [[ $# -ge 2 ]] || die "--customer-slug requires a value"
      CUSTOMER_SLUG="$2"
      shift 2
      ;;
    --aria-stage)
      [[ $# -ge 2 ]] || die "--aria-stage requires a value"
      ARIA_STAGE="$2"
      shift 2
      ;;
    --aria-tenant-id)
      [[ $# -ge 2 ]] || die "--aria-tenant-id requires a value"
      ARIA_TENANT_ID="$2"
      shift 2
      ;;
    --name)
      [[ $# -ge 2 ]] || die "--name requires a value"
      APP_NAME="$2"
      shift 2
      ;;
    --endpoint)
      [[ $# -ge 2 ]] || die "--endpoint requires a value"
      ENDPOINT="$2"
      shift 2
      ;;
    --microsoft-tenant-id)
      [[ $# -ge 2 ]] || die "--microsoft-tenant-id requires a value"
      EXPECTED_MICROSOFT_TENANT_ID="$2"
      shift 2
      ;;
    --developer-name)
      [[ $# -ge 2 ]] || die "--developer-name requires a value"
      DEVELOPER_NAME="$2"
      shift 2
      ;;
    --website-url)
      [[ $# -ge 2 ]] || die "--website-url requires a value"
      WEBSITE_URL="$2"
      shift 2
      ;;
    --privacy-url)
      [[ $# -ge 2 ]] || die "--privacy-url requires a value"
      PRIVACY_URL="$2"
      shift 2
      ;;
    --terms-url)
      [[ $# -ge 2 ]] || die "--terms-url requires a value"
      TERMS_URL="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || die "--output-dir requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --color-icon)
      [[ $# -ge 2 ]] || die "--color-icon requires a value"
      COLOR_ICON="$2"
      shift 2
      ;;
    --outline-icon)
      [[ $# -ge 2 ]] || die "--outline-icon requires a value"
      OUTLINE_ICON="$2"
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

for required in \
  CUSTOMER_SLUG ARIA_STAGE ARIA_TENANT_ID APP_NAME ENDPOINT \
  EXPECTED_MICROSOFT_TENANT_ID OUTPUT_DIR DEVELOPER_NAME \
  WEBSITE_URL PRIVACY_URL TERMS_URL; do
  [[ -n "${!required}" ]] || die "missing required input; run --help"
done

is_safe_slug "$CUSTOMER_SLUG" || die "--customer-slug must use a-z, 0-9, and hyphens"
is_safe_slug "$ARIA_STAGE" || die "--aria-stage must use a-z, 0-9, and hyphens"
is_safe_slug "$ARIA_TENANT_ID" || die "--aria-tenant-id must use a-z, 0-9, and hyphens"
is_uuid "$EXPECTED_MICROSOFT_TENANT_ID" ||
  die "--microsoft-tenant-id is not a valid UUID"
[[ "${#APP_NAME}" -le 30 ]] || die "--name cannot exceed 30 characters"
is_https_url "$ENDPOINT" || die "--endpoint must be HTTPS"
[[ "$ENDPOINT" == */teams/"$ARIA_TENANT_ID"/api/messages ]] ||
  die "--endpoint must end with /teams/$ARIA_TENANT_ID/api/messages"
is_https_url "$WEBSITE_URL" || die "--website-url must be HTTPS"
is_https_url "$PRIVACY_URL" || die "--privacy-url must be HTTPS"
is_https_url "$TERMS_URL" || die "--terms-url must be HTTPS"
if [[ -n "$COLOR_ICON" || -n "$OUTLINE_ICON" ]]; then
  [[ -n "$COLOR_ICON" && -n "$OUTLINE_ICON" ]] ||
    die "provide both icons or neither"
  [[ -f "$COLOR_ICON" ]] || die "color icon does not exist: $COLOR_ICON"
  [[ -f "$OUTLINE_ICON" ]] || die "outline icon does not exist: $OUTLINE_ICON"
fi

need_cmd "$TEAMS_BIN"
need_cmd jq
need_cmd awk
need_cmd unzip
if ! command -v sha256sum >/dev/null 2>&1; then
  need_cmd shasum
fi

TEAMS_CLI_VERSION="$("$TEAMS_BIN" --version | awk 'NR == 1 {print $1}')"
[[ "$TEAMS_CLI_VERSION" == "$REQUIRED_TEAMS_CLI_VERSION" ]] ||
  die "Teams CLI $REQUIRED_TEAMS_CLI_VERSION is validated; installed: $TEAMS_CLI_VERSION"

STATUS_JSON="$("$TEAMS_BIN" status --json)"
[[ "$(jq -r '.loggedIn // false' <<<"$STATUS_JSON")" == "true" ]] ||
  die "Teams CLI is not signed in; run: teams login"
SIGNED_IN_TENANT_ID="$(jq -r '.tenantId // empty' <<<"$STATUS_JSON")"
[[ "$(lower "$SIGNED_IN_TENANT_ID")" == "$(lower "$EXPECTED_MICROSOFT_TENANT_ID")" ]] ||
  die "Teams CLI is signed in to tenant $SIGNED_IN_TENANT_ID, not $EXPECTED_MICROSOFT_TENANT_ID"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
PUBLIC_HANDOFF="$OUTPUT_DIR/aria-msteams-handoff.json"
SECRET_HANDOFF="$OUTPUT_DIR/aria-msteams-secret.json"
MANIFEST_FILE="$OUTPUT_DIR/manifest.json"
PACKAGE_FILE="$OUTPUT_DIR/aria-msteams-app.zip"
DOCTOR_FILE="$OUTPUT_DIR/teams-doctor.json"
[[ ! -e "$PUBLIC_HANDOFF" && ! -e "$SECRET_HANDOFF" ]] ||
  die "output already contains an onboarding result; use a new folder to avoid duplicate apps"

CREDENTIALS_FILE="$(mktemp)"
MANIFEST_TMP="$(mktemp)"
trap 'rm -f "$CREDENTIALS_FILE" "$MANIFEST_TMP"' EXIT

CREATE_ARGS=(
  app create
  --name "$APP_NAME"
  --endpoint "$ENDPOINT"
  --env "$CREDENTIALS_FILE"
  --teams-managed
  --sign-in-audience myOrg
  --json
)
if [[ -n "$COLOR_ICON" ]]; then
  CREATE_ARGS+=(--color-icon "$COLOR_ICON" --outline-icon "$OUTLINE_ICON")
fi

echo "==> Creating single-tenant App Registration, Teams app, and Teams-managed bot"
CREATE_JSON="$("$TEAMS_BIN" "${CREATE_ARGS[@]}")"
TEAMS_APP_ID="$(jq -r '.teamsAppId // empty' <<<"$CREATE_JSON")"
BOT_APP_ID="$(jq -r '.botId // empty' <<<"$CREATE_JSON")"
BOT_LOCATION="$(jq -r '.botLocation // empty' <<<"$CREATE_JSON")"
INSTALL_LINK="$(jq -r '.installLink // empty' <<<"$CREATE_JSON")"
is_uuid "$TEAMS_APP_ID" || die "Teams CLI did not return a valid teamsAppId"
is_uuid "$BOT_APP_ID" || die "Teams CLI did not return a valid botId"
[[ "$BOT_LOCATION" == "teams-managed" ]] || die "the bot was not created as Teams-managed"

CLIENT_ID="$(env_value CLIENT_ID "$CREDENTIALS_FILE")"
CLIENT_SECRET="$(env_value CLIENT_SECRET "$CREDENTIALS_FILE")"
TENANT_ID="$(env_value TENANT_ID "$CREDENTIALS_FILE")"
[[ "$CLIENT_ID" == "$BOT_APP_ID" ]] || die "CLIENT_ID and botId do not match"
[[ -n "$CLIENT_SECRET" ]] || die "Teams CLI did not generate a client secret"
[[ "$(lower "$TENANT_ID")" == "$(lower "$EXPECTED_MICROSOFT_TENANT_ID")" ]] ||
  die "credentials were created in another tenant"

RSC_CSV="$(IFS=,; echo "${RSC_PERMISSIONS[*]}")"
echo "==> Applying the exact OpenClaw RSC baseline"
"$TEAMS_BIN" app rsc set "$TEAMS_APP_ID" \
  --permissions "$RSC_CSV" \
  --json >/dev/null

echo "==> Configuring publisher, URLs, and scopes"
"$TEAMS_BIN" app update "$TEAMS_APP_ID" \
  --endpoint "$ENDPOINT" \
  --scopes "personal,team,groupChat" \
  --name "$APP_NAME" \
  --long-name "$APP_NAME" \
  --short-description "ARIA assistant in Microsoft Teams" \
  --long-description "ARIA conversational assistant for authorized Microsoft Teams users and channels." \
  --developer "$DEVELOPER_NAME" \
  --website "$WEBSITE_URL" \
  --privacy-url "$PRIVACY_URL" \
  --terms-url "$TERMS_URL" \
  --json >/dev/null

echo "==> Enabling files in personal scope and validating manifest"
"$TEAMS_BIN" app manifest download "$TEAMS_APP_ID" "$MANIFEST_TMP"
jq --arg botId "$BOT_APP_ID" '
  if ([.bots[]? | select(.botId == $botId)] | length) != 1 then
    error("manifest botId mismatch")
  else
    (.bots[] | select(.botId == $botId) | .supportsFiles) = true
  end
' "$MANIFEST_TMP" >"$MANIFEST_FILE"
"$TEAMS_BIN" app manifest upload "$MANIFEST_FILE" "$TEAMS_APP_ID" --json >/dev/null
"$TEAMS_BIN" app manifest download "$TEAMS_APP_ID" "$MANIFEST_FILE"

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
        and ((.scopes - ["personal", "team", "groupChat"]) | length == 0)
        and ((["personal", "team", "groupChat"] - .scopes) | length == 0)
      )] | length == 1)
      and (.webApplicationInfo.id == $botId)
      and (($expectedRsc - $actualRsc) | length == 0)
      and (($actualRsc - $expectedRsc) | length == 0)
      and ((.authorization.permissions.resourceSpecific | length) == ($expectedRsc | length))
  ' "$MANIFEST_FILE" >/dev/null ||
  die "final manifest does not satisfy botId, scopes, supportsFiles, or RSC"

echo "==> Downloading app package and diagnostics"
"$TEAMS_BIN" app package download "$TEAMS_APP_ID" --output "$PACKAGE_FILE" >/dev/null
"$TEAMS_BIN" app doctor "$TEAMS_APP_ID" --json >"$DOCTOR_FILE"
DOCTOR_NON_SSO_FAILURES="$(
  jq '[.checks[]? | select(.status == "fail" and .category != "SSO")] | length' "$DOCTOR_FILE"
)"
[[ "$DOCTOR_NON_SSO_FAILURES" -eq 0 ]] ||
  die "teams app doctor reported non-SSO failures; review $DOCTOR_FILE"
PACKAGE_SHA256="$(sha256_file "$PACKAGE_FILE")"

jq -n \
  --arg appId "$CLIENT_ID" \
  --arg appPassword "$CLIENT_SECRET" \
  --arg tenantId "$TENANT_ID" \
  '{
    MSTEAMS_APP_ID: $appId,
    MSTEAMS_APP_PASSWORD: $appPassword,
    MSTEAMS_TENANT_ID: $tenantId,
    MSTEAMS_AUTH_TYPE: "secret"
  }' >"$SECRET_HANDOFF"

GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
DOCTOR_SUMMARY="$(jq '.summary' "$DOCTOR_FILE")"
DOCTOR_SSO_FAILURES="$(
  jq '[.checks[]? | select(.status == "fail" and .category == "SSO")] | length' "$DOCTOR_FILE"
)"
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --arg customerSlug "$CUSTOMER_SLUG" \
  --arg ariaStage "$ARIA_STAGE" \
  --arg ariaTenantId "$ARIA_TENANT_ID" \
  --arg endpoint "$ENDPOINT" \
  --arg microsoftTenantId "$TENANT_ID" \
  --arg teamsAppId "$TEAMS_APP_ID" \
  --arg botAppId "$BOT_APP_ID" \
  --arg appName "$APP_NAME" \
  --arg installLink "$INSTALL_LINK" \
  --arg packageFile "$(basename "$PACKAGE_FILE")" \
  --arg packageSha256 "$PACKAGE_SHA256" \
  --arg manifestFile "$(basename "$MANIFEST_FILE")" \
  --arg doctorFile "$(basename "$DOCTOR_FILE")" \
  --arg secretFile "$(basename "$SECRET_HANDOFF")" \
  --argjson rsc "$EXPECTED_RSC_JSON" \
  --argjson doctorSummary "$DOCTOR_SUMMARY" \
  --argjson doctorNonSsoFailures "$DOCTOR_NON_SSO_FAILURES" \
  --argjson doctorSsoFailures "$DOCTOR_SSO_FAILURES" \
  '{
    schemaVersion: 1,
    integration: "aria-openclaw-msteams",
    generatedAt: $generatedAt,
    customerSlug: $customerSlug,
    aria: {
      stage: $ariaStage,
      tenantId: $ariaTenantId,
      messagingEndpoint: $endpoint,
      secretName: ("aria/" + $ariaStage + "/tenant/" + $ariaTenantId + "/msteams")
    },
    microsoft: {
      tenantId: $microsoftTenantId,
      signInAudience: "AzureADMyOrg",
      teamsAppId: $teamsAppId,
      botAppId: $botAppId,
      botLocation: "teams-managed",
      appName: $appName
    },
    permissions: {
      model: "RSC",
      resourceSpecificApplication: $rsc,
      tenantWideGraphApplication: []
    },
    artifacts: {
      appPackage: $packageFile,
      appPackageSha256: $packageSha256,
      manifest: $manifestFile,
      doctor: $doctorFile,
      secretHandoff: $secretFile
    },
    installLink: $installLink,
    doctorSummary: $doctorSummary,
    doctorClassification: {
      nonSsoFailures: $doctorNonSsoFailures,
      ssoFailures: $doctorSsoFailures,
      ssoRequiredByAria: false
    }
  }' >"$PUBLIC_HANDOFF"

chmod 600 "$PUBLIC_HANDOFF" "$SECRET_HANDOFF" "$MANIFEST_FILE" "$PACKAGE_FILE" "$DOCTOR_FILE"

echo "==> Teams onboarding complete"
echo "    Handoff for ARIA (without secret): $PUBLIC_HANDOFF"
echo "    Secret for approved secure channel: $SECRET_HANDOFF"
echo "    Teams app package:              $PACKAGE_FILE"
echo "    Diagnostics:                    $DOCTOR_FILE"
echo ""
echo "The Microsoft administrator must install/approve the app only for authorized"
echo "users, teams, or chats. Install link:"
echo "  $INSTALL_LINK"
