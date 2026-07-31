#!/usr/bin/env bash
set -euo pipefail
umask 077

HANDOFF_FILE=""
TEAM_ID=""
TEST_USER_UPN=""
OUTPUT_FILE=""
TEAMS_BIN="${TEAMS_BIN:-teams}"
M365_BIN="${M365_BIN:-m365}"

usage() {
  cat <<'EOF'
Usage:
  verify-msteams-installation.sh \
    --handoff ./aria-example-microsoft/aria-msteams-handoff.json \
    --team-id 00000000-0000-0000-0000-000000000000 \
    [--test-user-upn user@example.com] \
    [--output ./aria-msteams-live-verification.json]

Verifies live Microsoft Teams onboarding without printing bot credentials:

  - Teams Developer Portal app and bot diagnostics;
  - matching single-tenant Entra App Registration;
  - organizational Teams app catalog publication;
  - installation in the specified Team;
  - exact Team-scoped RSC grants;
  - optional personal installation for a test user.

Prerequisites:
  teams login --device-code
  m365 login --authType deviceCode --appId <ADMIN_CLI_APP_ID> --tenant <TENANT_ID>

The m365 administrative app requires read access to the app catalog, Entra app
registrations, Teams app installations, and Team RSC permission grants.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

is_uuid() {
  [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --handoff)
      [[ $# -ge 2 ]] || die "--handoff requires a value"
      HANDOFF_FILE="$2"
      shift 2
      ;;
    --team-id)
      [[ $# -ge 2 ]] || die "--team-id requires a value"
      TEAM_ID="$2"
      shift 2
      ;;
    --test-user-upn)
      [[ $# -ge 2 ]] || die "--test-user-upn requires a value"
      TEST_USER_UPN="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || die "--output requires a value"
      OUTPUT_FILE="$2"
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

[[ -n "$HANDOFF_FILE" ]] || die "--handoff is required"
[[ -f "$HANDOFF_FILE" ]] || die "handoff file does not exist: $HANDOFF_FILE"
[[ -n "$TEAM_ID" ]] || die "--team-id is required"
is_uuid "$TEAM_ID" || die "--team-id is not a valid UUID"

for command_name in "$TEAMS_BIN" "$M365_BIN" jq; do
  command -v "$command_name" >/dev/null 2>&1 ||
    die "missing required command: $command_name"
done

MICROSOFT_TENANT_ID="$(jq -er '.microsoft.tenantId' "$HANDOFF_FILE")" ||
  die "handoff is missing microsoft.tenantId"
TEAMS_APP_ID="$(jq -er '.microsoft.teamsAppId' "$HANDOFF_FILE")" ||
  die "handoff is missing microsoft.teamsAppId"
BOT_APP_ID="$(jq -er '.microsoft.botAppId' "$HANDOFF_FILE")" ||
  die "handoff is missing microsoft.botAppId"
APP_NAME="$(jq -er '.microsoft.appName' "$HANDOFF_FILE")" ||
  die "handoff is missing microsoft.appName"
EXPECTED_ENDPOINT="$(jq -er '.aria.messagingEndpoint' "$HANDOFF_FILE")" ||
  die "handoff is missing aria.messagingEndpoint"
EXPECTED_GROUP_RSC="$(
  jq '[.permissions.resourceSpecificApplication[] | select(endswith(".Group"))] | sort' \
    "$HANDOFF_FILE"
)"

is_uuid "$MICROSOFT_TENANT_ID" || die "handoff Microsoft tenant ID is invalid"
is_uuid "$TEAMS_APP_ID" || die "handoff Teams app ID is invalid"
is_uuid "$BOT_APP_ID" || die "handoff bot app ID is invalid"

if [[ -z "$OUTPUT_FILE" ]]; then
  OUTPUT_FILE="$(dirname "$HANDOFF_FILE")/aria-msteams-live-verification.json"
fi
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "==> Verifying Teams Developer CLI connection"
TEAMS_STATUS="$($TEAMS_BIN status --json)"
[[ "$(jq -r '.loggedIn // false' <<<"$TEAMS_STATUS")" == "true" ]] ||
  die "Teams CLI is logged out; run: teams login --device-code"
TEAMS_TENANT_ID="$(jq -r '.tenantId // empty' <<<"$TEAMS_STATUS")"
[[ "$(lower "$TEAMS_TENANT_ID")" == "$(lower "$MICROSOFT_TENANT_ID")" ]] ||
  die "Teams CLI is connected to tenant $TEAMS_TENANT_ID, not $MICROSOFT_TENANT_ID"

TEAMS_APP="$($TEAMS_BIN app get "$TEAMS_APP_ID" --json)"
[[ "$(jq -r '.teamsAppId // empty' <<<"$TEAMS_APP")" == "$TEAMS_APP_ID" ]] ||
  die "Teams Developer Portal app was not found"
[[ "$(jq -r '.endpoint // empty' <<<"$TEAMS_APP")" == "$EXPECTED_ENDPOINT" ]] ||
  die "Teams app endpoint does not match the handoff"

TEAMS_DOCTOR="$($TEAMS_BIN app doctor "$TEAMS_APP_ID" --json)"
DOCTOR_NON_SSO_FAILURES="$(
  jq '[.checks[]? | select(.status == "fail" and .category != "SSO")] | length' \
    <<<"$TEAMS_DOCTOR"
)"
[[ "$DOCTOR_NON_SSO_FAILURES" -eq 0 ]] ||
  die "Teams app doctor reported non-SSO failures"

echo "==> Verifying CLI for Microsoft 365 connection"
M365_STATUS="$($M365_BIN status --output json)"
[[ "$M365_STATUS" != '"Logged out"' ]] ||
  die "CLI for Microsoft 365 is logged out"
M365_TENANT_ID="$(jq -r '.appTenant // empty' <<<"$M365_STATUS")"
[[ "$(lower "$M365_TENANT_ID")" == "$(lower "$MICROSOFT_TENANT_ID")" ]] ||
  die "m365 is connected to tenant $M365_TENANT_ID, not $MICROSOFT_TENANT_ID"

echo "==> Verifying Entra App Registration"
ENTRA_APP="$($M365_BIN entra app get \
  --appId "$BOT_APP_ID" \
  --properties appId,displayName,signInAudience \
  --output json)" ||
  die "cannot read the Entra app; the m365 administrative identity needs Application.Read.All or Directory.Read.All"
[[ "$(jq -r '.appId // empty' <<<"$ENTRA_APP")" == "$BOT_APP_ID" ]] ||
  die "Entra App Registration was not found"
[[ "$(jq -r '.signInAudience // empty' <<<"$ENTRA_APP")" == "AzureADMyOrg" ]] ||
  die "Entra app is not single-tenant"

echo "==> Verifying organizational app catalog"
CATALOG_APPS="$($M365_BIN teams app list \
  --distributionMethod organization \
  --output json)" ||
  die "cannot read the Teams app catalog; the m365 administrative identity needs AppCatalog.Read.All"
CATALOG_APP="$(
  jq -c --arg teamsAppId "$TEAMS_APP_ID" \
    '[.[] | select((.externalId // "" | ascii_downcase) == ($teamsAppId | ascii_downcase))] | first // empty' \
    <<<"$CATALOG_APPS"
)"
[[ -n "$CATALOG_APP" ]] ||
  die "Teams app $TEAMS_APP_ID is not published in the organization catalog"
CATALOG_ID="$(jq -r '.id' <<<"$CATALOG_APP")"

echo "==> Verifying Team installation"
TEAM_APPS="$($M365_BIN teams team app list --teamId "$TEAM_ID" --output json)" ||
  die "cannot read Team app installations"
jq -e --arg catalogId "$CATALOG_ID" --arg teamsAppId "$TEAMS_APP_ID" '
  any(.[].teamsApp?;
    ((.id // "" | ascii_downcase) == ($catalogId | ascii_downcase))
    or ((.externalId // "" | ascii_downcase) == ($teamsAppId | ascii_downcase))
  )
' <<<"$TEAM_APPS" >/dev/null ||
  die "Teams app is not installed in Team $TEAM_ID"

echo "==> Verifying Team RSC grants"
PERMISSION_GRANTS="$($M365_BIN request \
  --url "https://graph.microsoft.com/v1.0/teams/$TEAM_ID/permissionGrants" \
  --method get \
  --output json)" ||
  die "cannot read Team RSC permission grants"
ACTUAL_GROUP_RSC="$(
  jq --arg botAppId "$BOT_APP_ID" '
    [
      (.value // .)[]
      | select(
          (((.clientAppId // .clientId // "") | ascii_downcase)
            == ($botAppId | ascii_downcase))
          and ((.permissionType // "") | ascii_downcase) == "application"
        )
      | .permission
    ]
    | sort
  ' <<<"$PERMISSION_GRANTS"
)"
[[ "$ACTUAL_GROUP_RSC" == "$EXPECTED_GROUP_RSC" ]] ||
  die "Team RSC grants do not exactly match the handoff"

USER_INSTALLED="null"
if [[ -n "$TEST_USER_UPN" ]]; then
  echo "==> Verifying optional personal installation"
  USER_APPS="$($M365_BIN teams user app list \
    --userName "$TEST_USER_UPN" \
    --output json)" ||
    die "cannot read personal app installations for $TEST_USER_UPN"
  if jq -e --arg catalogId "$CATALOG_ID" --arg teamsAppId "$TEAMS_APP_ID" '
    any(.[].teamsApp?;
      ((.id // "" | ascii_downcase) == ($catalogId | ascii_downcase))
      or ((.externalId // "" | ascii_downcase) == ($teamsAppId | ascii_downcase))
    )
  ' <<<"$USER_APPS" >/dev/null; then
    USER_INSTALLED="true"
  else
    die "Teams app is not installed personally for $TEST_USER_UPN"
  fi
fi

GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --arg tenantId "$MICROSOFT_TENANT_ID" \
  --arg teamsAppId "$TEAMS_APP_ID" \
  --arg botAppId "$BOT_APP_ID" \
  --arg appName "$APP_NAME" \
  --arg endpoint "$EXPECTED_ENDPOINT" \
  --arg catalogId "$CATALOG_ID" \
  --arg teamId "$TEAM_ID" \
  --arg testUserUpn "$TEST_USER_UPN" \
  --argjson rsc "$ACTUAL_GROUP_RSC" \
  --argjson userInstalled "$USER_INSTALLED" \
  --argjson doctorSummary "$(jq '.summary' <<<"$TEAMS_DOCTOR")" \
  '{
    schemaVersion: 1,
    integration: "aria-openclaw-msteams-live-verification",
    generatedAt: $generatedAt,
    tenantId: $tenantId,
    teamsAppId: $teamsAppId,
    botAppId: $botAppId,
    appName: $appName,
    endpoint: $endpoint,
    catalogId: $catalogId,
    teamId: $teamId,
    testUserUpn: (if $testUserUpn == "" then null else $testUserUpn end),
    checks: {
      teamsDeveloperPortal: true,
      botDiagnostics: true,
      entraAppRegistration: true,
      organizationCatalog: true,
      teamInstallation: true,
      teamRsc: true,
      personalInstallation: $userInstalled
    },
    teamRscPermissions: $rsc,
    doctorSummary: $doctorSummary
  }' >"$OUTPUT_FILE"

chmod 600 "$OUTPUT_FILE"
echo "==> Live Teams onboarding verification passed"
echo "    Report: $OUTPUT_FILE"
