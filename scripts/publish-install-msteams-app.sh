#!/usr/bin/env bash
set -euo pipefail
umask 077

HANDOFF_FILE=""
TEAM_ID=""
PACKAGE_FILE=""
OUTPUT_FILE=""
M365_BIN="${M365_BIN:-m365}"
POLL_INTERVAL="${ARIA_MSTEAMS_POLL_INTERVAL:-5}"
POLL_ATTEMPTS="${ARIA_MSTEAMS_POLL_ATTEMPTS:-12}"

usage() {
  cat <<'EOF'
Usage:
  publish-install-msteams-app.sh \
    --handoff ./aria-example-microsoft/aria-msteams-handoff.json \
    --team-id 00000000-0000-0000-0000-000000000000 \
    [--package ./aria-example-microsoft/aria-msteams-app.zip] \
    [--output ./aria-example-microsoft/aria-msteams-installation.json]

Automates the administrative phase after bot provisioning:

  - verifies the Microsoft tenant and package checksum;
  - publishes the package to the organization app catalog when absent;
  - installs the catalog app in the specified Team through Microsoft Graph;
  - includes the exact Team-scoped RSC consentedPermissionSet;
  - verifies the Team installation and RSC grants;
  - writes a non-secret installation report.

Prerequisite interactive login:
  m365 login --authType deviceCode \
    --appId <TEAMS_ONBOARDING_ADMIN_CLI_APP_ID> \
    --tenant <MICROSOFT_TENANT_ID>

The dedicated administrative CLI app needs delegated Microsoft Graph access:
  AppCatalog.ReadWrite.All
  TeamsAppInstallation.ReadWriteAndConsentForTeam
  TeamsAppInstallation.ReadForTeam

Application.Read.All is additionally required by the separate live verifier.
The signed-in user must be authorized to publish organization apps and install
apps in the target Team. CLI for Microsoft 365 documents Global Administrator
as required for its catalog publish command.

This script is idempotent: it reuses an existing catalog publication and Team
installation that match the manifest App ID. It never reads or prints the bot
secret.
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
    --package)
      [[ $# -ge 2 ]] || die "--package requires a value"
      PACKAGE_FILE="$2"
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
[[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]] || die "ARIA_MSTEAMS_POLL_INTERVAL must be a non-negative integer"
[[ "$POLL_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || die "ARIA_MSTEAMS_POLL_ATTEMPTS must be a positive integer"

for command_name in "$M365_BIN" jq awk; do
  command -v "$command_name" >/dev/null 2>&1 ||
    die "missing required command: $command_name"
done
if ! command -v sha256sum >/dev/null 2>&1; then
  command -v shasum >/dev/null 2>&1 || die "missing required command: shasum"
fi

MICROSOFT_TENANT_ID="$(jq -er '.microsoft.tenantId' "$HANDOFF_FILE")" ||
  die "handoff is missing microsoft.tenantId"
TEAMS_APP_ID="$(jq -er '.microsoft.teamsAppId' "$HANDOFF_FILE")" ||
  die "handoff is missing microsoft.teamsAppId"
BOT_APP_ID="$(jq -er '.microsoft.botAppId' "$HANDOFF_FILE")" ||
  die "handoff is missing microsoft.botAppId"
APP_NAME="$(jq -er '.microsoft.appName' "$HANDOFF_FILE")" ||
  die "handoff is missing microsoft.appName"
EXPECTED_PACKAGE_SHA="$(jq -er '.artifacts.appPackageSha256' "$HANDOFF_FILE")" ||
  die "handoff is missing artifacts.appPackageSha256"
EXPECTED_GROUP_RSC="$(
  jq '[.permissions.resourceSpecificApplication[] | select(endswith(".Group"))] | sort' \
    "$HANDOFF_FILE"
)"

is_uuid "$MICROSOFT_TENANT_ID" || die "handoff Microsoft tenant ID is invalid"
is_uuid "$TEAMS_APP_ID" || die "handoff Teams app ID is invalid"
is_uuid "$BOT_APP_ID" || die "handoff bot app ID is invalid"
[[ "$EXPECTED_PACKAGE_SHA" =~ ^[0-9a-fA-F]{64}$ ]] ||
  die "handoff package checksum is invalid"
[[ "$(jq 'length' <<<"$EXPECTED_GROUP_RSC")" -gt 0 ]] ||
  die "handoff declares no Team-scoped RSC permissions"

if [[ -z "$PACKAGE_FILE" ]]; then
  PACKAGE_FILE="$(dirname "$HANDOFF_FILE")/$(jq -r '.artifacts.appPackage' "$HANDOFF_FILE")"
fi
[[ -f "$PACKAGE_FILE" ]] || die "Teams app package does not exist: $PACKAGE_FILE"
ACTUAL_PACKAGE_SHA="$(sha256_file "$PACKAGE_FILE")"
[[ "$(lower "$ACTUAL_PACKAGE_SHA")" == "$(lower "$EXPECTED_PACKAGE_SHA")" ]] ||
  die "Teams app package checksum does not match the handoff"

if [[ -z "$OUTPUT_FILE" ]]; then
  OUTPUT_FILE="$(dirname "$HANDOFF_FILE")/aria-msteams-installation.json"
fi
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "==> Verifying CLI for Microsoft 365 connection"
M365_STATUS="$($M365_BIN status --output json)"
[[ "$M365_STATUS" != '"Logged out"' ]] ||
  die "m365 is logged out; run the administrative device-code login shown in --help"
M365_TENANT_ID="$(jq -r '.appTenant // empty' <<<"$M365_STATUS")"
[[ "$(lower "$M365_TENANT_ID")" == "$(lower "$MICROSOFT_TENANT_ID")" ]] ||
  die "m365 is connected to tenant $M365_TENANT_ID, not $MICROSOFT_TENANT_ID"
ADMIN_CONNECTED_AS="$(jq -r '.connectedAs // empty' <<<"$M365_STATUS")"
ADMIN_APP_ID="$(jq -r '.appId // empty' <<<"$M365_STATUS")"

echo "==> Resolving organization catalog app"
CATALOG_APPS="$($M365_BIN teams app list \
  --distributionMethod organization \
  --output json)" ||
  die "cannot read the catalog; the admin CLI app needs AppCatalog.ReadWrite.All"
CATALOG_APP="$(
  jq -c --arg teamsAppId "$TEAMS_APP_ID" \
    '[.[] | select((.externalId // "" | ascii_downcase) == ($teamsAppId | ascii_downcase))] | first // empty' \
    <<<"$CATALOG_APPS"
)"
PUBLISHED_NOW=false
if [[ -z "$CATALOG_APP" ]]; then
  echo "==> Publishing package to the organization catalog"
  CATALOG_APP="$($M365_BIN teams app publish \
    --filePath "$PACKAGE_FILE" \
    --output json)" ||
    die "catalog publication failed; use a Global Administrator and AppCatalog.ReadWrite.All"
  PUBLISHED_NOW=true
fi

CATALOG_ID="$(jq -r '.id // empty' <<<"$CATALOG_APP")"
CATALOG_EXTERNAL_ID="$(jq -r '.externalId // empty' <<<"$CATALOG_APP")"
is_uuid "$CATALOG_ID" || die "catalog response did not contain a valid catalog ID"
[[ "$(lower "$CATALOG_EXTERNAL_ID")" == "$(lower "$TEAMS_APP_ID")" ]] ||
  die "catalog app external ID does not match the handoff Teams app ID"

team_installation_exists() {
  local team_apps
  team_apps="$($M365_BIN teams team app list --teamId "$TEAM_ID" --output json)" ||
    return 2
  jq -e --arg catalogId "$CATALOG_ID" --arg teamsAppId "$TEAMS_APP_ID" '
    any(.[];
      ((.teamsApp.id // "" | ascii_downcase) == ($catalogId | ascii_downcase))
      or ((.teamsApp.externalId // "" | ascii_downcase) == ($teamsAppId | ascii_downcase))
    )
  ' <<<"$team_apps" >/dev/null
}

INSTALLED_NOW=false
if team_installation_exists; then
  echo "==> Matching app is already installed in the Team"
else
  install_status=$?
  [[ "$install_status" -ne 2 ]] ||
    die "cannot list Team apps; verify TeamsAppInstallation.ReadForTeam and target Team access"

  INSTALL_BODY_FILE="$(mktemp)"
  trap 'rm -f "$INSTALL_BODY_FILE"' EXIT
  jq -n \
    --arg catalogId "$CATALOG_ID" \
    --argjson rsc "$EXPECTED_GROUP_RSC" \
    '{
      "teamsApp@odata.bind":
        ("https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/" + $catalogId),
      consentedPermissionSet: {
        resourceSpecificPermissions: [
          $rsc[] | {
            permissionValue: .,
            permissionType: "application"
          }
        ]
      }
    }' >"$INSTALL_BODY_FILE"

  echo "==> Installing app in the Team with explicit RSC consent"
  $M365_BIN request \
    --url "https://graph.microsoft.com/v1.0/teams/$TEAM_ID/installedApps" \
    --method post \
    --body "@$INSTALL_BODY_FILE" \
    --output none ||
    die "Team installation failed; verify TeamsAppInstallation.ReadWriteAndConsentForTeam, Team access, and tenant RSC settings"
  INSTALLED_NOW=true

  installation_found=false
  for ((attempt = 1; attempt <= POLL_ATTEMPTS; attempt++)); do
    if team_installation_exists; then
      installation_found=true
      break
    fi
    sleep "$POLL_INTERVAL"
  done
  [[ "$installation_found" == true ]] ||
    die "Team installation was submitted but was not observable before the timeout"
fi

echo "==> Verifying Team RSC grants"
PERMISSION_GRANTS="$($M365_BIN request \
  --url "https://graph.microsoft.com/v1.0/teams/$TEAM_ID/permissionGrants" \
  --method get \
  --output json)" ||
  die "cannot read Team RSC grants; the admin CLI app needs TeamsAppInstallation.ReadForTeam"
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

GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --arg tenantId "$MICROSOFT_TENANT_ID" \
  --arg teamsAppId "$TEAMS_APP_ID" \
  --arg botAppId "$BOT_APP_ID" \
  --arg appName "$APP_NAME" \
  --arg catalogId "$CATALOG_ID" \
  --arg teamId "$TEAM_ID" \
  --arg packageSha256 "$ACTUAL_PACKAGE_SHA" \
  --arg connectedAs "$ADMIN_CONNECTED_AS" \
  --arg adminAppId "$ADMIN_APP_ID" \
  --argjson publishedNow "$PUBLISHED_NOW" \
  --argjson installedNow "$INSTALLED_NOW" \
  --argjson rsc "$ACTUAL_GROUP_RSC" \
  '{
    schemaVersion: 1,
    integration: "aria-msteams-catalog-team-installation",
    generatedAt: $generatedAt,
    tenantId: $tenantId,
    teamsAppId: $teamsAppId,
    botAppId: $botAppId,
    appName: $appName,
    catalogId: $catalogId,
    teamId: $teamId,
    packageSha256: $packageSha256,
    administrativeConnection: {
      connectedAs: $connectedAs,
      appId: $adminAppId
    },
    actions: {
      publishedNow: $publishedNow,
      installedNow: $installedNow
    },
    checks: {
      packageChecksum: true,
      tenantMatch: true,
      organizationCatalog: true,
      teamInstallation: true,
      teamRsc: true
    },
    teamRscPermissions: $rsc
  }' >"$OUTPUT_FILE"

chmod 600 "$OUTPUT_FILE"
echo "==> Teams app catalog publication and Team installation passed"
echo "    Catalog ID: $CATALOG_ID"
echo "    Team ID: $TEAM_ID"
echo "    Report: $OUTPUT_FILE"
