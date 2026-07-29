#!/usr/bin/env bash
#
# Create or update a single-tenant App Registration for CLI for Microsoft 365
# (clim365). It is a public client with delegated permissions: no client secret
# is created.
#
# The customer Microsoft administrator runs this script after:
#   az login --tenant <TENANT_ID> --allow-no-subscriptions
#
set -euo pipefail
umask 077

GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"
SHAREPOINT_APP_ID="00000003-0000-0ff1-ce00-000000000000"
REDIRECT_URI="https://login.microsoftonline.com/common/oauth2/nativeclient"
M365_CLI_VERSION="v11.10.0"
BASE_GRAPH_SCOPES=(
  "openid"
  "profile"
  "email"
  "offline_access"
  "User.Read"
)

APP_NAME=""
EXPECTED_TENANT_ID=""
EXISTING_APP_ID=""
OUTPUT_DIR=""
INTEGRATION_USER_UPN=""
SHAREPOINT_SITE_URL=""
SHAREPOINT_FOLDER_URL=""
GRANT_ADMIN_CONSENT=true
ENABLE_OUTLOOK=true
ENABLE_CALENDAR=true
ENABLE_SHAREPOINT=true
ENABLE_DRIVE=true
EXTRA_GRAPH_SCOPES=()
EXTRA_SHAREPOINT_SCOPES=()

usage() {
  cat <<'EOF'
Usage:
  provision-clim365-app.sh \
    --name "ARIA - Contoso - Microsoft 365 Integration" \
    --tenant-id 00000000-0000-0000-0000-000000000000 \
    --integration-user-upn aria.integration@contoso.com \
    --enable-all \
    --sharepoint-site-url "https://contoso.sharepoint.com/sites/ARIA" \
    --sharepoint-folder-url "Shared Documents/ARIA" \
    --output-dir ./aria-contoso-microsoft

What this creates:
  A single-tenant Microsoft Entra public client app for CLI for Microsoft 365.
  The app uses delegated device-code login and does not create a client secret.

Required before running:
  Bash, Node.js 20+, npm, jq, Azure CLI, and CLI for Microsoft 365 11.10.0.
  ./scripts/check-m365-prerequisites.sh
  npm install -g @pnp/cli-microsoft365@11.10.0
  m365 version
  az login --tenant <TENANT_ID> --allow-no-subscriptions
  The az login user must be able to create/manage App Registrations and
  Enterprise Applications. Use Cloud Application Administrator, Application
  Administrator, Privileged Role Administrator, or Global Administrator for the
  full script path with tenant-wide admin consent. If consent is handled by a
  separate administrator, run this script with --skip-admin-consent.

Inputs:
  --name NAME                       App Registration display name.
  --tenant-id UUID                  Expected Microsoft tenant. Must match az account show.
  --integration-user-upn UPN        Dedicated delegated user ARIA will use and verify.
  --worker-user-upn UPN             Backward-compatible alias for --integration-user-upn.
  --enable-outlook                  Include Mail.ReadWrite and Mail.Send for the user's mailbox.
  --enable-calendar                 Include Calendars.ReadWrite for the user's calendar.
  --enable-sharepoint               Include Sites.ReadWrite.All and AllSites.Write.
  --enable-drive                    Include Files.ReadWrite for the user's OneDrive.
  --enable-all                      Enable Outlook, Calendar, SharePoint, and Drive (default).
  --disable-outlook                 Exclude Outlook permissions.
  --disable-calendar                Exclude Calendar permissions.
  --disable-sharepoint              Exclude SharePoint permissions.
  --disable-drive                   Exclude OneDrive permissions.
  --sharepoint-site-url URL         Required with --enable-sharepoint; operational site URL.
  --sharepoint-folder-url PATH      Required with --enable-sharepoint; SharePoint folder path,
                                    for example /Shared Documents/ARIA, not /ARIA from Graph Drive.
  --output-dir PATH                 Private folder where the ARIA handoff will be written.
  --existing-app-id UUID            Update an existing App Registration instead of creating one.
  --extra-scope SCOPE               Additional Microsoft Graph delegated scope; repeatable.
  --extra-sharepoint-scope SCOPE    Additional SharePoint delegated scope; repeatable.
  --skip-admin-consent              Configure permissions but do not run admin consent.
  --print-input-template            Print a fillable command template and exit.
  -h, --help                        Show this help.

Microsoft Graph base scopes always included:
  openid profile email offline_access User.Read

By default, Outlook, Calendar, SharePoint, and Drive are enabled. Use
--disable-* flags to exclude a workload from the requested consent.

Security notes:
  No client secret is created. clim365 uses device-code login as the integration
  user. AllSites.Write and Sites.ReadWrite.All do not exceed the signed-in
  user's permissions; use a dedicated account with access only to approved
  sites. Files.ReadWrite grants read/write access to that user's OneDrive; use
  --disable-drive if only SharePoint libraries are needed.

Outputs:
  aria-m365-integration-handoff.json

Next verification step:
  m365 login --authType deviceCode --appId <APP_ID> --tenant <TENANT_ID>
  ./scripts/verify-clim365-access.sh --handoff <handoff.json>

The Microsoft Graph Site ID is not an input. It is resolved from
--sharepoint-site-url after the first login by verify-clim365-access.sh.
EOF
}

print_input_template() {
  cat <<'EOF'
# Fill these values before running the Microsoft 365 onboarding script.
# Do not put passwords, MFA codes, refresh tokens, or client secrets in this file.
# INTEGRATION_USER_UPN is the dedicated delegated runtime identity, not a tenant
# restriction on the App Registration.
MICROSOFT_TENANT_ID="00000000-0000-0000-0000-000000000000"
INTEGRATION_USER_UPN="aria.integration@contoso.com"
APP_NAME="ARIA - Contoso - Microsoft 365 Integration"
SHAREPOINT_SITE_URL="https://contoso.sharepoint.com/sites/ARIA"
SHAREPOINT_FOLDER_URL="Shared Documents/ARIA"
OUTPUT_DIR="./aria-contoso-microsoft"

az login --tenant "$MICROSOFT_TENANT_ID" --allow-no-subscriptions

./scripts/provision-clim365-app.sh \
  --name "$APP_NAME" \
  --tenant-id "$MICROSOFT_TENANT_ID" \
  --integration-user-upn "$INTEGRATION_USER_UPN" \
  --enable-all \
  --sharepoint-site-url "$SHAREPOINT_SITE_URL" \
  --sharepoint-folder-url "$SHAREPOINT_FOLDER_URL" \
  --output-dir "$OUTPUT_DIR"
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

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      [[ $# -ge 2 ]] || die "--name requires a value"
      APP_NAME="$2"
      shift 2
      ;;
    --tenant-id)
      [[ $# -ge 2 ]] || die "--tenant-id requires a value"
      EXPECTED_TENANT_ID="$2"
      shift 2
      ;;
    --integration-user-upn|--worker-user-upn)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      INTEGRATION_USER_UPN="$2"
      shift 2
      ;;
    --enable-outlook)
      ENABLE_OUTLOOK=true
      shift
      ;;
    --enable-calendar)
      ENABLE_CALENDAR=true
      shift
      ;;
    --enable-sharepoint)
      ENABLE_SHAREPOINT=true
      shift
      ;;
    --enable-drive)
      ENABLE_DRIVE=true
      shift
      ;;
    --enable-all)
      ENABLE_OUTLOOK=true
      ENABLE_CALENDAR=true
      ENABLE_SHAREPOINT=true
      ENABLE_DRIVE=true
      shift
      ;;
    --disable-outlook)
      ENABLE_OUTLOOK=false
      shift
      ;;
    --disable-calendar)
      ENABLE_CALENDAR=false
      shift
      ;;
    --disable-sharepoint)
      ENABLE_SHAREPOINT=false
      shift
      ;;
    --disable-drive)
      ENABLE_DRIVE=false
      shift
      ;;
    --sharepoint-site-url)
      [[ $# -ge 2 ]] || die "--sharepoint-site-url requires a value"
      SHAREPOINT_SITE_URL="$2"
      shift 2
      ;;
    --sharepoint-folder-url)
      [[ $# -ge 2 ]] || die "--sharepoint-folder-url requires a value"
      SHAREPOINT_FOLDER_URL="$2"
      shift 2
      ;;
    --existing-app-id)
      [[ $# -ge 2 ]] || die "--existing-app-id requires a value"
      EXISTING_APP_ID="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || die "--output-dir requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --extra-scope)
      [[ $# -ge 2 ]] || die "--extra-scope requires a value"
      EXTRA_GRAPH_SCOPES+=("$2")
      shift 2
      ;;
    --extra-sharepoint-scope)
      [[ $# -ge 2 ]] || die "--extra-sharepoint-scope requires a value"
      EXTRA_SHAREPOINT_SCOPES+=("$2")
      shift 2
      ;;
    --skip-admin-consent)
      GRANT_ADMIN_CONSENT=false
      shift
      ;;
    --print-input-template)
      print_input_template
      exit 0
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

[[ -n "$APP_NAME" ]] || die "--name is required"
[[ -n "$EXPECTED_TENANT_ID" ]] || die "--tenant-id is required"
[[ -n "$INTEGRATION_USER_UPN" ]] || die "--integration-user-upn is required"
[[ -n "$OUTPUT_DIR" ]] || die "--output-dir is required"
[[ "$ENABLE_OUTLOOK" == true || "$ENABLE_CALENDAR" == true ||
  "$ENABLE_SHAREPOINT" == true || "$ENABLE_DRIVE" == true ]] ||
  die "select at least one workload: --enable-outlook, --enable-calendar, --enable-sharepoint, or --enable-drive"
is_uuid "$EXPECTED_TENANT_ID" || die "--tenant-id is not a valid UUID"
[[ "$INTEGRATION_USER_UPN" =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]] ||
  die "--integration-user-upn does not look like a valid UPN"
if [[ "$ENABLE_SHAREPOINT" == true ]]; then
  [[ -n "$SHAREPOINT_SITE_URL" ]] || die "--sharepoint-site-url is required with --enable-sharepoint"
  [[ -n "$SHAREPOINT_FOLDER_URL" ]] || die "--sharepoint-folder-url is required with --enable-sharepoint"
  [[ "$SHAREPOINT_SITE_URL" == https://* ]] ||
    die "--sharepoint-site-url must be HTTPS"
  [[ "$SHAREPOINT_SITE_URL" != *"?"* && "$SHAREPOINT_SITE_URL" != *"#"* &&
    "$SHAREPOINT_SITE_URL" != *[[:space:]]* ]] ||
    die "--sharepoint-site-url cannot include a query string, fragment, or unencoded spaces"
  SHAREPOINT_SITE_URL="${SHAREPOINT_SITE_URL%/}"
  SHAREPOINT_HOSTNAME="${SHAREPOINT_SITE_URL#https://}"
  SHAREPOINT_HOSTNAME="${SHAREPOINT_HOSTNAME%%/*}"
  case "$SHAREPOINT_HOSTNAME" in
    *.sharepoint.com|*.sharepoint.us|*.sharepoint.de|*.sharepoint.cn) ;;
    *) die "--sharepoint-site-url does not use a recognized SharePoint Online hostname" ;;
  esac
  SHAREPOINT_SITE_PATH="${SHAREPOINT_SITE_URL#https://$SHAREPOINT_HOSTNAME}"
  [[ -n "$SHAREPOINT_SITE_PATH" ]] || SHAREPOINT_SITE_PATH="/"
  [[ "$SHAREPOINT_FOLDER_URL" != *".."* && "$SHAREPOINT_FOLDER_URL" != *"?"* &&
    "$SHAREPOINT_FOLDER_URL" != *"#"* ]] ||
    die "--sharepoint-folder-url cannot include .., a query string, or a fragment"
else
  SHAREPOINT_SITE_URL=""
  SHAREPOINT_FOLDER_URL=""
  SHAREPOINT_HOSTNAME=""
  SHAREPOINT_SITE_PATH=""
fi
if [[ -n "$EXISTING_APP_ID" ]]; then
  is_uuid "$EXISTING_APP_ID" || die "--existing-app-id is not a valid UUID"
fi

need_cmd az
need_cmd jq

ACCOUNT_JSON="$(az account show --output json --only-show-errors 2>/dev/null)" ||
  die "Azure CLI is not signed in; run: az login --tenant $EXPECTED_TENANT_ID --allow-no-subscriptions"
SIGNED_IN_TENANT_ID="$(jq -r '.tenantId // empty' <<<"$ACCOUNT_JSON")"
[[ "$(lower "$SIGNED_IN_TENANT_ID")" == "$(lower "$EXPECTED_TENANT_ID")" ]] ||
  die "Azure CLI is signed in to tenant $SIGNED_IN_TENANT_ID, not $EXPECTED_TENANT_ID"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
HANDOFF_FILE="$OUTPUT_DIR/aria-m365-integration-handoff.json"
[[ ! -e "$HANDOFF_FILE" ]] ||
  die "$HANDOFF_FILE already exists; move it or use a new folder before repeating onboarding"

GRAPH_SCOPES=("${BASE_GRAPH_SCOPES[@]}")
[[ "$ENABLE_OUTLOOK" == true ]] && GRAPH_SCOPES+=("Mail.ReadWrite" "Mail.Send")
[[ "$ENABLE_CALENDAR" == true ]] && GRAPH_SCOPES+=("Calendars.ReadWrite")
[[ "$ENABLE_SHAREPOINT" == true ]] && GRAPH_SCOPES+=("Sites.ReadWrite.All")
[[ "$ENABLE_DRIVE" == true ]] && GRAPH_SCOPES+=("Files.ReadWrite")
if [[ "${#EXTRA_GRAPH_SCOPES[@]}" -gt 0 ]]; then
  for scope in "${EXTRA_GRAPH_SCOPES[@]}"; do
    GRAPH_SCOPES+=("$scope")
  done
fi
UNIQUE_GRAPH_SCOPES=()
for scope in "${GRAPH_SCOPES[@]}"; do
  [[ -n "$scope" ]] || die "an --extra-scope value is empty"
  already_present=false
  if [[ "${#UNIQUE_GRAPH_SCOPES[@]}" -gt 0 ]]; then
    for current in "${UNIQUE_GRAPH_SCOPES[@]}"; do
      if [[ "$current" == "$scope" ]]; then
        already_present=true
        break
      fi
    done
  fi
  if [[ "$already_present" == false ]]; then
    UNIQUE_GRAPH_SCOPES+=("$scope")
  fi
done

echo "==> Checking Microsoft Graph scopes in tenant $EXPECTED_TENANT_ID"
GRAPH_SP_JSON="$(az ad sp show --id "$GRAPH_APP_ID" --output json --only-show-errors)"
GRAPH_RESOURCE_ACCESS='[]'
for scope in "${UNIQUE_GRAPH_SCOPES[@]}"; do
  scope_id="$(
    jq -r --arg value "$scope" '
      ((.oauth2PermissionScopes // []) + (.oauth2Permissions // []))
      | map(select(.value == $value and (.isEnabled // true)))
      | .[0].id // empty
    ' <<<"$GRAPH_SP_JSON"
  )"
  [[ -n "$scope_id" ]] || die "Microsoft Graph does not expose delegated scope: $scope"
  GRAPH_RESOURCE_ACCESS="$(
    jq --arg id "$scope_id" --arg value "$scope" \
      '. + [{id: $id, type: "Scope", value: $value}]' <<<"$GRAPH_RESOURCE_ACCESS"
  )"
done

SHAREPOINT_SCOPES=()
[[ "$ENABLE_SHAREPOINT" == true ]] && SHAREPOINT_SCOPES+=("AllSites.Write")
if [[ "${#EXTRA_SHAREPOINT_SCOPES[@]}" -gt 0 ]]; then
  for scope in "${EXTRA_SHAREPOINT_SCOPES[@]}"; do
    SHAREPOINT_SCOPES+=("$scope")
  done
fi
UNIQUE_SHAREPOINT_SCOPES=()
for scope in "${SHAREPOINT_SCOPES[@]}"; do
  [[ -n "$scope" ]] || die "an --extra-sharepoint-scope value is empty"
  already_present=false
  if [[ "${#UNIQUE_SHAREPOINT_SCOPES[@]}" -gt 0 ]]; then
    for current in "${UNIQUE_SHAREPOINT_SCOPES[@]}"; do
      if [[ "$current" == "$scope" ]]; then
        already_present=true
        break
      fi
    done
  fi
  if [[ "$already_present" == false ]]; then
    UNIQUE_SHAREPOINT_SCOPES+=("$scope")
  fi
done

SHAREPOINT_RESOURCE_ACCESS='[]'
if [[ "${#UNIQUE_SHAREPOINT_SCOPES[@]}" -gt 0 ]]; then
  echo "==> Checking SharePoint Online scopes in tenant $EXPECTED_TENANT_ID"
  SHAREPOINT_SP_JSON="$(az ad sp show --id "$SHAREPOINT_APP_ID" --output json --only-show-errors)"
  for scope in "${UNIQUE_SHAREPOINT_SCOPES[@]}"; do
    scope_id="$(
      jq -r --arg value "$scope" '
        ((.oauth2PermissionScopes // []) + (.oauth2Permissions // []))
        | map(select(.value == $value and (.isEnabled // true)))
        | .[0].id // empty
      ' <<<"$SHAREPOINT_SP_JSON"
    )"
    [[ -n "$scope_id" ]] || die "SharePoint Online does not expose delegated scope: $scope"
    SHAREPOINT_RESOURCE_ACCESS="$(
      jq --arg id "$scope_id" --arg value "$scope" \
        '. + [{id: $id, type: "Scope", value: $value}]' <<<"$SHAREPOINT_RESOURCE_ACCESS"
    )"
  done
fi

REQUIRED_ACCESS_FILE="$(mktemp)"
trap 'rm -f "$REQUIRED_ACCESS_FILE"' EXIT
jq -n \
  --arg graphAppId "$GRAPH_APP_ID" \
  --arg sharePointAppId "$SHAREPOINT_APP_ID" \
  --argjson graphAccess "$GRAPH_RESOURCE_ACCESS" \
  --argjson sharePointAccess "$SHAREPOINT_RESOURCE_ACCESS" \
  '[
    {
      resourceAppId: $graphAppId,
      resourceAccess: ($graphAccess | map({id, type}))
    }
  ] + (if ($sharePointAccess | length) > 0 then [
    {
      resourceAppId: $sharePointAppId,
      resourceAccess: ($sharePointAccess | map({id, type}))
    }
  ] else [] end)' >"$REQUIRED_ACCESS_FILE"

CREATED=false
if [[ -n "$EXISTING_APP_ID" ]]; then
  echo "==> Updating App Registration $EXISTING_APP_ID"
  az ad app show --id "$EXISTING_APP_ID" --output none --only-show-errors
  az ad app update \
    --id "$EXISTING_APP_ID" \
    --display-name "$APP_NAME" \
    --sign-in-audience AzureADMyOrg \
    --is-fallback-public-client true \
    --public-client-redirect-uris "$REDIRECT_URI" \
    --required-resource-accesses "@$REQUIRED_ACCESS_FILE" \
    --output none \
    --only-show-errors
  APP_ID="$EXISTING_APP_ID"
else
  escaped_name="${APP_NAME//\'/\'\'}"
  SAME_NAME_APPS="$(
    az ad app list \
      --filter "displayName eq '$escaped_name'" \
      --query '[].appId' \
      --output json \
      --only-show-errors
  )"
  if [[ "$(jq 'length' <<<"$SAME_NAME_APPS")" -gt 0 ]]; then
    ids="$(jq -r 'join(", ")' <<<"$SAME_NAME_APPS")"
    die "an App Registration with this name already exists ($ids); use --existing-app-id explicitly"
  fi

  echo "==> Creating single-tenant App Registration"
  APP_JSON="$(
    az ad app create \
      --display-name "$APP_NAME" \
      --sign-in-audience AzureADMyOrg \
      --is-fallback-public-client true \
      --public-client-redirect-uris "$REDIRECT_URI" \
      --required-resource-accesses "@$REQUIRED_ACCESS_FILE" \
      --output json \
      --only-show-errors
  )"
  APP_ID="$(jq -r '.appId' <<<"$APP_JSON")"
  CREATED=true
fi

echo "==> Checking Service Principal"
if ! az ad sp show --id "$APP_ID" --output none --only-show-errors 2>/dev/null; then
  az ad sp create --id "$APP_ID" --output none --only-show-errors
fi

ADMIN_CONSENT_GRANTED=false
if [[ "$GRANT_ADMIN_CONSENT" == true ]]; then
  echo "==> Granting admin consent for declared scopes"
  az ad app permission admin-consent \
    --id "$APP_ID" \
    --output none \
    --only-show-errors
  ADMIN_CONSENT_GRANTED=true
else
  echo "==> Admin consent skipped by --skip-admin-consent"
fi

FINAL_APP_JSON="$(az ad app show --id "$APP_ID" --output json --only-show-errors)"
OBJECT_ID="$(jq -r '.id' <<<"$FINAL_APP_JSON")"
SIGN_IN_AUDIENCE="$(jq -r '.signInAudience' <<<"$FINAL_APP_JSON")"
IS_PUBLIC_CLIENT="$(jq -r '.isFallbackPublicClient' <<<"$FINAL_APP_JSON")"
[[ "$SIGN_IN_AUDIENCE" == "AzureADMyOrg" ]] ||
  die "the resulting app is not single-tenant: $SIGN_IN_AUDIENCE"
[[ "$IS_PUBLIC_CLIENT" == "true" ]] ||
  die "the resulting app does not allow public client flows"

GRAPH_SCOPES_JSON="$(printf '%s\n' "${UNIQUE_GRAPH_SCOPES[@]}" | jq -R . | jq -s .)"
if [[ "${#UNIQUE_SHAREPOINT_SCOPES[@]}" -gt 0 ]]; then
  SHAREPOINT_SCOPES_JSON="$(printf '%s\n' "${UNIQUE_SHAREPOINT_SCOPES[@]}" | jq -R . | jq -s .)"
else
  SHAREPOINT_SCOPES_JSON='[]'
fi
if [[ "$ENABLE_SHAREPOINT" == true ]]; then
  GRAPH_SITE_LOOKUP_URL="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_HOSTNAME}:${SHAREPOINT_SITE_PATH}"
else
  GRAPH_SITE_LOOKUP_URL=""
fi
WORKLOADS_JSON="$(
  jq -n \
    --argjson outlook "$ENABLE_OUTLOOK" \
    --argjson calendar "$ENABLE_CALENDAR" \
    --argjson sharePoint "$ENABLE_SHAREPOINT" \
    --argjson drive "$ENABLE_DRIVE" \
    '{outlook:$outlook,calendar:$calendar,sharePoint:$sharePoint,drive:$drive}'
)"
GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --arg tenantId "$EXPECTED_TENANT_ID" \
  --arg appId "$APP_ID" \
  --arg objectId "$OBJECT_ID" \
  --arg displayName "$APP_NAME" \
  --arg redirectUri "$REDIRECT_URI" \
  --arg integrationUserUpn "$INTEGRATION_USER_UPN" \
  --arg sharePointSiteUrl "$SHAREPOINT_SITE_URL" \
  --arg sharePointHostname "$SHAREPOINT_HOSTNAME" \
  --arg sharePointSitePath "$SHAREPOINT_SITE_PATH" \
  --arg sharePointFolderUrl "$SHAREPOINT_FOLDER_URL" \
  --arg graphSiteLookupUrl "$GRAPH_SITE_LOOKUP_URL" \
  --arg m365CliVersion "$M365_CLI_VERSION" \
  --argjson graphScopes "$GRAPH_SCOPES_JSON" \
  --argjson sharePointScopes "$SHAREPOINT_SCOPES_JSON" \
  --argjson workloads "$WORKLOADS_JSON" \
  --argjson created "$CREATED" \
  --argjson adminConsentGranted "$ADMIN_CONSENT_GRANTED" \
  '{
    schemaVersion: 3,
    integration: "aria-clim365-integration",
    generatedAt: $generatedAt,
    tenantId: $tenantId,
    appId: $appId,
    appObjectId: $objectId,
    displayName: $displayName,
    signInAudience: "AzureADMyOrg",
    publicClient: true,
    redirectUri: $redirectUri,
    workloads: $workloads,
    delegatedPermissions: $graphScopes,
    permissions: {
      microsoftGraph: {
        resourceAppId: "00000003-0000-0000-c000-000000000000",
        delegated: $graphScopes
      },
      sharePointOnline: {
        resourceAppId: "00000003-0000-0ff1-ce00-000000000000",
        delegated: $sharePointScopes
      }
    },
    delegatedIdentity: {
      userPrincipalName: $integrationUserUpn,
      accessBoundary: "The app cannot exceed the permissions of this signed-in user."
    },
    sharePoint: (if $workloads.sharePoint then {
      siteUrl: $sharePointSiteUrl,
      hostname: $sharePointHostname,
      sitePath: $sharePointSitePath,
      defaultFolderUrl: $sharePointFolderUrl,
      graphSiteId: null,
      graphSiteIdRequiredAsInput: false,
      graphSiteLookupUrl: $graphSiteLookupUrl,
      authorizationBoundary: "Operational default only; effective authorization is the integration user membership."
    } else null end),
    cli: {
      package: "@pnp/cli-microsoft365",
      testedVersion: $m365CliVersion,
      skill: "pnp/cli-microsoft365 skills/clim365"
    },
    created: $created,
    adminConsentGranted: $adminConsentGranted,
    ariaRuntime: {
      CLIMICROSOFT365_ENTRAAPPID: $appId,
      CLIMICROSOFT365_TENANT: $tenantId,
      authentication: "delegated-device-code",
      clientSecretRequired: false,
      enabledWorkloads: $workloads
    }
  }' >"$HANDOFF_FILE"

chmod 600 "$HANDOFF_FILE"

echo "==> clim365 onboarding complete"
echo "    Public/controlled handoff: $HANDOFF_FILE"
echo "    App (client) ID: $APP_ID"
echo "    Tenant ID: $EXPECTED_TENANT_ID"
echo ""
echo "Next step: the ARIA operator configures these two IDs and runs once:"
echo "  m365 login --authType deviceCode --appId $APP_ID --tenant $EXPECTED_TENANT_ID"
echo "The login must be completed as: $INTEGRATION_USER_UPN"
echo "Then verify enabled workloads and resolve the Site ID:"
echo "  ./scripts/verify-clim365-access.sh --handoff \"$HANDOFF_FILE\""
