# Microsoft Customer Onboarding

This document covers two independent Microsoft onboarding tracks:

| Track | Purpose | Required for the other track? | Main script |
| --- | --- | --- | --- |
| Microsoft 365 delegated integration | Outlook, Calendar, SharePoint, and OneDrive through `@pnp/cli-microsoft365` / `clim365` | No | `./scripts/provision-clim365-app.sh` |
| Microsoft Teams channel | OpenClaw conversational channel in Microsoft Teams through Bot Framework | No | `./scripts/provision-aria-msteams-bot.sh` |

Do not treat these tracks as dependencies. A customer can enable Microsoft 365
delegated tools without enabling Microsoft Teams. A customer can enable the
Teams channel without enabling Outlook, Calendar, SharePoint, or OneDrive. They
use separate App Registrations, separate runtime configuration, and separate
secrets.

If the customer also enables ARIA's native app-only SharePoint tools, keep that
as a third identity. Do not merge it with either track above.

| Identity | Use | Authentication | Effective scope |
| --- | --- | --- | --- |
| `ARIA Microsoft 365 Integration` | `clim365` delegated actions | Public client, device code, no client secret | Signed-in integration user plus delegated scopes |
| `ARIA Teams Bot` | Teams channel | Teams-managed bot plus client secret | RSC on the team/chat where the app is installed |
| `ARIA SharePoint Native` | Background `aria_sharepoint_*` tools | Confidential client plus client secret | Graph `Sites.Selected` plus per-site `write` grant |

## Ownership Model

The customer owns Microsoft tenant facts:

- Microsoft Tenant ID;
- Microsoft administrator account and consent authority;
- integration user UPN, mailbox, calendar, OneDrive, and SharePoint membership;
- SharePoint site URL and folder path;
- Teams app publisher/developer name, legal URLs, installation policy, and
  catalog approval policy;
- final approval for all delegated scopes, RSC permissions, and write probes.

ARIA owns ARIA runtime facts:

- ARIA stage, for example `staging`;
- ARIA tenant/instance ID, for example `contoso`;
- public Teams messaging endpoint, if the Teams channel is enabled;
- target Secrets Manager names under `aria/<stage>/tenant/<tenant_id>/...`;
- gateway runtime provider setting, channel overlay, allowlists, and runtime
  reload/deploy.

The scripts generate the Microsoft IDs and handoff artifacts that the ARIA
operator needs. ARIA should not invent the customer Microsoft Tenant ID,
integration UPN, SharePoint URL, or customer legal URLs.

## Common Prerequisites

The customer Microsoft administrator needs:

- a Bash-compatible shell, such as macOS, Linux, WSL, or a CI runner with Bash;
- Git, or a ZIP download of the customer onboarding repository;
- Node.js 20+ and npm;
- `jq`;
- a private output folder for generated artifacts;
- a Microsoft Entra user that can create and manage App Registrations and
  Enterprise Applications in the customer Microsoft tenant;
- admin-consent authority if the script should grant tenant-wide admin consent;
- Azure CLI (`az`) for the Microsoft 365 delegated integration track.

For the full Microsoft 365 delegated integration script path, including admin
consent, the user authenticated with `az login` should have one of these
Microsoft Entra roles:

- Cloud Application Administrator;
- Application Administrator;
- Privileged Role Administrator;
- Global Administrator.

`Cloud Application Administrator` or `Application Administrator` is normally
enough for this package because it requests delegated permissions only. If the
customer separates app creation from admin consent, run
`provision-clim365-app.sh` with `--skip-admin-consent`, then have an authorized
administrator review and grant admin consent separately.

Install only the CLI required for the selected track:

```bash
# Microsoft 365 delegated integration only
npm install -g @pnp/cli-microsoft365@11.10.0
m365 version

# Microsoft Teams channel only
npm install -g @microsoft/teams.cli@3.0.3
teams --version
```

After cloning or downloading the customer onboarding repository, check the
workstation first:

```bash
./scripts/check-m365-prerequisites.sh
```

If the checker reports missing tools, use one of the install blocks below or the
customer's approved software distribution process, then close and reopen the
terminal and run the checker again.

Windows PowerShell, run as Administrator:

```powershell
winget install --exact --id Git.Git
winget install --exact --id OpenJS.NodeJS.LTS
winget install --exact --id jqlang.jq
winget install --exact --id Microsoft.AzureCLI
npm install -g @pnp/cli-microsoft365@11.10.0
```

Close and reopen the terminal after `winget` installs the tools. Run the shell
scripts from Git Bash, WSL, or another Bash-compatible shell.

macOS:

```bash
command -v brew >/dev/null 2>&1 || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew update
brew install git node jq azure-cli
npm install -g @pnp/cli-microsoft365@11.10.0
```

Ubuntu or WSL:

```bash
sudo apt-get update
sudo apt-get install -y git curl jq ca-certificates
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash
. "$HOME/.nvm/nvm.sh"
nvm install --lts
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
npm install -g @pnp/cli-microsoft365@11.10.0
```

If security policy blocks direct install scripts from the internet, install
Node.js, Azure CLI, and CLI for Microsoft 365 through the organization's
approved software catalog instead.

For a quick manual preflight:

```bash
node --version
npm --version
jq --version
az version
m365 version
```

The scripts verify the signed-in Microsoft Tenant ID before creating resources.

## Track A: Microsoft 365 Delegated Integration

Use this track when ARIA needs delegated access to the integration user's
Outlook mailbox, calendar, OneDrive, or approved SharePoint sites through
`clim365`.

This track does not create a Teams app or bot.

### Customer Inputs

The customer must resolve or approve these values before running the script.

| Input | Example | Owner | Notes |
| --- | --- | --- | --- |
| Microsoft Tenant ID | `00000000-0000-0000-0000-000000000000` | Customer | Used by `az login` and `--tenant-id`; prevents wrong-tenant setup |
| Integration user UPN | `aria.integration@contoso.com` | Customer | Dedicated non-admin user whose mailbox, calendar, OneDrive, and SharePoint access bound ARIA |
| Enabled workloads | Outlook, Calendar, SharePoint, Drive | Customer + ARIA | Use `--disable-*` flags to reduce scope |
| Microsoft 365 app display name | `ARIA - Contoso - Microsoft 365 Integration` | Customer + ARIA | Naming convention can be suggested by ARIA, approved by customer |
| SharePoint site URL | `https://contoso.sharepoint.com/sites/ARIA` | Customer | Required only when SharePoint is enabled |
| SharePoint folder URL | `Shared Documents/ARIA` | Customer | Required only when SharePoint is enabled; must be valid for `m365 spo` |
| Existing app ID | UUID | Customer | Optional; use only when updating an existing App Registration |
| Admin consent mode | grant or skip | Customer | `--skip-admin-consent` configures permissions but does not grant consent |

`SHAREPOINT_SITE_ID` is not an input. Microsoft Graph resolves it by path after
the first delegated login.

`--sharepoint-folder-url` must be a path accepted by SharePoint Online commands,
for example `/Shared Documents/ARIA` or `Shared Documents/ARIA`. Do not use a
Graph drive-relative path like `/ARIA`; that may work for native `driveItem`
logic, but it does not identify a document library for `m365 spo file add`.

For an agent-friendly command template, run:

```bash
./scripts/provision-clim365-app.sh --print-input-template
```

### ARIA Inputs To Customer

ARIA should provide only the ARIA-side intent and execution package:

- the script version or repository package the customer should run;
- requested workload list, for example Outlook + Calendar + SharePoint, no
  Drive;
- suggested app display-name convention;
- approved secure handoff channel for generated artifacts;
- ARIA stage and ARIA tenant ID only so the operator can later seed the correct
  secret. These values are not Microsoft script inputs.

### Customer Execution

```bash
az login --tenant <MICROSOFT_TENANT_ID> --allow-no-subscriptions
az account show --query '{tenantId:tenantId,user:user.name}' --output json

./scripts/provision-clim365-app.sh \
  --name "ARIA - Contoso - Microsoft 365 Integration" \
  --tenant-id "<MICROSOFT_TENANT_ID>" \
  --integration-user-upn "aria.integration@contoso.com" \
  --enable-all \
  --sharepoint-site-url "https://contoso.sharepoint.com/sites/ARIA" \
  --sharepoint-folder-url "Shared Documents/ARIA" \
  --output-dir "./aria-contoso-microsoft"
```

The script creates:

- `signInAudience=AzureADMyOrg`;
- public client flows;
- the official native-client redirect URI;
- the service principal;
- admin consent, unless `--skip-admin-consent` is used;
- `aria-m365-integration-handoff.json`.

### Delegated Permissions

| Resource | Scope | Use |
| --- | --- | --- |
| Microsoft Graph | `openid`, `profile`, `email`, `offline_access` | Identity and renewable session |
| Microsoft Graph | `User.Read` | Confirm the signed-in user |
| Microsoft Graph | `Mail.ReadWrite` | Read, organize, and modify the integration user's mailbox |
| Microsoft Graph | `Mail.Send` | Send mail as the integration user |
| Microsoft Graph | `Calendars.ReadWrite` | Read and manage the integration user's calendar |
| Microsoft Graph | `Files.ReadWrite` | Read/write the integration user's OneDrive |
| Microsoft Graph | `Sites.ReadWrite.All` | Resolve SharePoint Site ID and operate SharePoint content through Graph |
| SharePoint Online | `AllSites.Write` | Run `m365 spo` read/write commands, including `spo file add` |

Microsoft Graph and SharePoint Online are separate OAuth resources. A Graph
`Sites.ReadWrite.All` token does not by itself authorize `m365 spo ...`
commands; those commands need a SharePoint Online token with `AllSites.Write`.

The permission names describe the maximum delegated scopes the app can request,
but delegated mode does not elevate the signed-in user. The practical security
boundary is the dedicated integration user: no admin roles, only approved
SharePoint memberships, and a controlled OneDrive if Drive is enabled.

The app does not include application permissions and does not include access to
other users' mailboxes. For approved shared-mailbox cases, pass additional
delegated Graph scopes explicitly:

```bash
--extra-scope Mail.ReadWrite.Shared
--extra-scope Calendars.ReadWrite.Shared
--extra-scope Mail.Send.Shared
```

Do not add `Mail.ReadWrite` Application, `Sites.FullControl.All`,
`AllSites.FullControl`, or other broad permissions without a documented use case
and security approval.

### Customer Outputs To ARIA

The customer sends these artifacts to ARIA:

| Artifact | Sensitivity | Required by ARIA | Notes |
| --- | --- | --- | --- |
| `aria-m365-integration-handoff.json` | Internal, non-secret | Yes | Contains App ID, Tenant ID, UPN, workload flags, scopes, SharePoint URL/folder, and runtime config |
| Admin consent confirmation | Internal | Yes | Human confirmation or audit evidence that consent was granted or intentionally skipped |
| Integration user access confirmation | Internal | Yes | Confirms mailbox/calendar licensing and approved SharePoint membership |

The handoff contains configuration but no password, client secret, access token,
refresh token, or MFA material. ARIA must never ask the customer to send those
by email, chat, or ticket.

The handoff gives ARIA these runtime values:

```text
CLIMICROSOFT365_ENTRAAPPID=<app/client id>
CLIMICROSOFT365_TENANT=<tenant id>
```

### ARIA Operator Settings

After receiving the handoff, the ARIA operator applies Microsoft 365 settings
to the ARIA tenant:

1. Validate and store the handoff:

   ```bash
   # ARIA internal repository; this script is not included in the customer package.
   ./scripts/seed-tenant-clim365-secrets.sh <aria-stage> <aria-tenant-id> \
     --handoff ./aria-contoso-microsoft/aria-m365-integration-handoff.json
   ```

   This writes:

   ```text
   aria/<stage>/tenant/<tenant_id>/microsoft365
   ```

2. Deploy or reload the gateway so the entrypoint materializes the handoff into
   tenant-private EFS state and exports:

   ```text
   CLIMICROSOFT365_ENTRAAPPID=<app/client id>
   CLIMICROSOFT365_TENANT=<tenant id>
   ```

3. Start the delegated login from the tenant's persistent runtime environment:

   ```bash
   m365 login \
     --authType deviceCode \
     --appId <APP_ID> \
     --tenant <TENANT_ID>
   ```

   The customer completes the device-code flow in their browser as the declared
   integration user. The ARIA operator does not receive the password or MFA
   factors.

4. Verify runtime access:

   ```bash
   ./scripts/verify-clim365-access.sh \
     --handoff ./aria-contoso-microsoft/aria-m365-integration-handoff.json
   ```

   The output is normally produced by the ARIA operator after the ARIA runtime
   login:

   ```text
   aria-m365-access-verification.json
   ```

   If the customer runs this verifier on their own machine, treat that as a
   preflight only. ARIA still needs its own runtime login and verification.

5. Set `workspaceProvider: microsoft` only if this ARIA tenant should use
   Microsoft 365 as the automatic inbox, calendar, and file provider. If the
   tenant remains Google-backed and `clim365` is only present for controlled
   testing, leave `workspaceProvider` as `google`.

6. Enable the `clim365` skill and exact exec allowlist only for the surfaces
   approved for Microsoft 365 operations.

### Runtime Cache And Verification

With CLI for Microsoft 365 `11.10.0`, the connection cache is stored under
`HOME` as `.cli-m365-msal.json`, `.cli-m365-connection.json`, and
`.cli-m365-all-connections.json`. In the ARIA gateway, these files must be
linked to `OPENCLAW_STATE_DIR/credentials/clim365` on EFS with `0600` file
permissions before login.

Microsoft authentication and command execution approval are separate layers. For
the main agent to use this integration, all of these must be true:

1. the image contains `/usr/local/bin/m365` `11.10.0` and the `clim365` skill;
2. `openclaw.json` enables `clim365` and `exec` for `main`;
3. both the persistent file and active copy of `exec-approvals.json` allow the
   launcher `/usr/local/bin/m365` and the resolved npm target for `main`.

The effective allowlist entry must be equivalent to:

```json
{
  "agents": {
    "main": {
      "allowlist": [
        {
          "id": "<stable-uuid>",
          "pattern": "/usr/local/bin/m365"
        },
        {
          "id": "<different-stable-uuid>",
          "pattern": "/usr/local/lib/node_modules/@pnp/cli-microsoft365/dist/index.js"
        }
      ]
    }
  }
}
```

Keep `security=allowlist`, `ask=off`, and `autoAllowSkills=false`. Do not allow
`sh`, `bash`, `node`, `npm`, `npx`, `ls`, or wildcard patterns. Keep `m365`
available only to `main`; the approved Microsoft send path runs from `main`
directly, not from `outreach-coordinator`.

For each exact command, the `clim365` skill requires a separate exec call with
`--help options` before the operation. Do not combine the help and operation
with shell chaining, pipes, or wrappers.

Final validation must go through the agent, not only ECS Exec:

1. start a test session with `main`;
2. ask it to use `clim365` with absolute commands and separate calls;
3. for normal mail, validate draft -> explicit approval -> send;
4. send a test to the integration user's own mailbox;
5. verify receipt and `saveToSentItems`;
6. confirm that the effective `lastUsedCommand` is `/usr/local/bin/m365`,
   without printing tokens.

## Track B: Microsoft Teams Channel

Use this track only when ARIA should be available as a conversational channel in
Microsoft Teams.

This track does not enable Outlook, Calendar, SharePoint, OneDrive, `clim365`,
or `workspaceProvider: microsoft`.

### Customer Inputs

The customer must resolve or approve these values before running the Teams
script.

| Input | Example | Owner | Notes |
| --- | --- | --- | --- |
| Microsoft Tenant ID | `00000000-0000-0000-0000-000000000000` | Customer | Used by `teams login` and `--microsoft-tenant-id` |
| Teams app name | `ARIA Contoso` | Customer + ARIA | Visible name, max 30 characters |
| Developer/publisher name | `ARIA` or customer legal publisher | Customer + ARIA | Shown in Teams manifest |
| Website URL | `https://example.com` | Customer + ARIA | Teams manifest website |
| Privacy URL | `https://example.com/privacy` | Customer + ARIA | Teams manifest privacy policy |
| Terms URL | `https://example.com/terms` | Customer + ARIA | Teams manifest terms |
| Optional icons | `color.png`, `outline.png` | Customer + ARIA | Color 192x192 PNG and outline 32x32 PNG |
| Installation policy | approved users, teams, chats | Customer | Customer controls where the app is installed |

### ARIA Inputs To Customer

ARIA must provide these values before the customer runs the Teams script.

| Input | Example | Why it matters |
| --- | --- | --- |
| Customer slug | `contoso` | Traceability in handoff artifacts |
| ARIA stage | `staging` | Determines ARIA secret path and runtime stage |
| ARIA tenant ID | `contoso` | Used in the public endpoint route |
| Messaging endpoint | `https://<api>/teams/contoso/api/messages` | Bot Framework callback URL |
| Secure handoff instructions | approved secret channel | Required for `aria-msteams-secret.json` |

The Teams endpoint must end exactly with:

```text
/teams/<aria-tenant-id>/api/messages
```

Do not include tokens, query strings, or fragments.

### Customer Execution

```bash
teams login
teams status --json

./scripts/provision-aria-msteams-bot.sh \
  --customer-slug "contoso" \
  --aria-stage "staging" \
  --aria-tenant-id "contoso" \
  --name "ARIA Contoso" \
  --endpoint "https://<api>/teams/contoso/api/messages" \
  --microsoft-tenant-id "<MICROSOFT_TENANT_ID>" \
  --developer-name "ARIA" \
  --website-url "https://example.com" \
  --privacy-url "https://example.com/privacy" \
  --terms-url "https://example.com/terms" \
  --output-dir "./aria-contoso-microsoft"
```

Optional branding:

```bash
--color-icon ./color.png --outline-icon ./outline.png
```

The script:

1. verifies Teams CLI `3.0.3`, login, and Tenant ID;
2. creates a single-tenant Entra app, Teams app, and Teams-managed bot;
3. sets the public ARIA endpoint;
4. applies the exact OpenClaw RSC baseline;
5. sets scopes `personal`, `team`, and `groupChat`;
6. enables DM file attachments with `supportsFiles: true`;
7. downloads and validates the manifest and package;
8. runs `teams app doctor`;
9. separates public and secret outputs.

### Teams RSC Permissions

The Teams package declares these `Application` resource-specific consent
permissions:

```text
ChannelMessage.Read.Group
ChannelMessage.Send.Group
Member.Read.Group
Owner.Read.Group
ChannelSettings.Read.Group
TeamMember.Read.Group
TeamSettings.Read.Group
ChatMessage.Read.Chat
```

RSC is limited to the team/chat where the app is installed. The baseline does
not add tenant-wide Microsoft Graph application permissions.

### Customer Outputs To ARIA

The customer sends these artifacts to ARIA:

| Artifact | Sensitivity | Required by ARIA | Notes |
| --- | --- | --- | --- |
| `aria-msteams-handoff.json` | Internal | Yes | Bot/Teams IDs, endpoint, RSC, install link, package hash |
| `aria-msteams-secret.json` | Secret | Yes | `MSTEAMS_APP_ID`, `MSTEAMS_APP_PASSWORD`, `MSTEAMS_TENANT_ID`, `MSTEAMS_AUTH_TYPE` |
| `aria-msteams-app.zip` | Internal | Yes for install/catalog workflows | Teams app package |
| `manifest.json` | Internal | Recommended | Auditable manifest |
| `teams-doctor.json` | Internal | Recommended | Teams diagnostics |

Send `aria-msteams-secret.json` only through the approved secret channel. Do not
send it by email, chat, or ticket attachment.

Before handoff, validate without printing secret values:

```bash
./scripts/validate-msteams-handoff.sh \
  ./aria-contoso-microsoft/aria-msteams-handoff.json \
  ./aria-contoso-microsoft/aria-msteams-secret.json
```

### ARIA Operator Settings

After receiving the Teams handoff, the ARIA operator applies Teams channel
settings to the ARIA tenant:

1. Validate the handoff:

   ```bash
   ./scripts/validate-msteams-handoff.sh \
     ./aria-contoso-microsoft/aria-msteams-handoff.json \
     ./aria-contoso-microsoft/aria-msteams-secret.json
   ```

2. Seed the Teams secret:

   ```bash
   # ARIA internal repository; this script is not included in the customer package.
   ./scripts/seed-tenant-msteams-secrets.sh <aria-stage> <aria-tenant-id> \
     --secret-json ./aria-contoso-microsoft/aria-msteams-secret.json
   ```

   This writes:

   ```text
   aria/<stage>/tenant/<tenant_id>/msteams
   ```

3. Enable or update the tenant runtime overlay for `channels.msteams` only if
   the Teams channel is approved for that tenant. Keep DM pairing and group
   allowlists closed until stable IDs are approved.

4. Reload runtime or deploy:

   ```bash
   pnpm run ecs:gateway:reload-runtime -- <aria-stage> <aria-tenant-id>
   ```

5. Test DM pairing first, then open teams/channels only with stable team,
   channel, chat, and user IDs.

The Teams operator settings do not set `CLIMICROSOFT365_*`, do not store a
`microsoft365` handoff, and do not change `workspaceProvider`.

### Install Or Approve The Teams App

For a controlled test, open the `installLink` from the handoff and install the
app for the test user. For teams/chats, the installer sees and accepts RSC for
that specific resource.

For the organization catalog:

- Teams Admin Center can upload `aria-msteams-app.zip`; or
- a Global Administrator can use:

  ```bash
  m365 teams app publish --filePath ./aria-msteams-app.zip
  ```

Microsoft Graph publishing for Teams apps uses delegated permissions:
`AppCatalog.Submit` is the least privileged submission scope;
`AppCatalog.ReadWrite.All` allows direct publication. Application/app-only is
not supported for this operation. Do not add these permissions to the runtime
for onboarding convenience; use a separate administrative identity and remove
the scope after completion.

After publication, `m365 teams app install` can install from the catalog by
`teamId` or user. The `id` accepted by that command is the catalog ID, not the
manifest ID.

## Operation And Revocation

Microsoft 365 delegated integration:

- The App Registration has no client secret.
- Revoke sessions/tokens and disable the Enterprise Application to cut access.
- The delegated token cache in EFS is a credential and must be protected,
  backed up, and removed during offboarding.
- Changing `workspaceProvider` back to `google` stops automatic Microsoft
  provider behavior but does not by itself revoke Microsoft tokens.

Microsoft Teams channel:

- Rotate the bot client secret according to the customer's policy.
- Uninstalling the Teams app revokes RSC for that resource.
- Disabling `channels.msteams.enabled` stops the ARIA Teams channel.
- Revoking the bot secret invalidates sends and proactive replies.

## Relationship To Native ARIA SharePoint Tools

Do not reuse the public/delegated Microsoft 365 App Registration as the
credential for native `aria_sharepoint_*` tools.

| Path | Authentication | Permission | Site ID/Drive ID |
| --- | --- | --- | --- |
| `clim365` skill plus `m365` | Device code, delegated user | Graph `Sites.ReadWrite.All` plus SharePoint `AllSites.Write` | Site ID is resolved; `spo` commands use `webUrl` |
| Native ARIA tools | Client credentials, app-only | Graph `Sites.Selected` plus per-site `write` grant | Site ID and Drive ID are required in the ECS secret |

The native path already supports background SharePoint operations in staging.
Keeping the registrations separate reduces the impact of a compromised token or
secret.

ARIA keeps the staging evaluation for promoting `clim365` without disabling the
native path in its internal runbooks. That runbook is not part of this customer
package.

## Official References

- [OpenClaw: Microsoft Teams](https://docs.openclaw.ai/channels/msteams)
- [Microsoft Teams CLI registration quickstart](https://learn.microsoft.com/en-us/microsoftteams/platform/teams-sdk/get-started/quickstart-register)
- [Microsoft Teams RSC](https://learn.microsoft.com/en-us/microsoftteams/platform/graph-api/rsc/resource-specific-consent)
- [Microsoft: grant RSC in the app manifest](https://learn.microsoft.com/en-us/microsoftteams/platform/graph-api/rsc/grant-resource-specific-consent)
- [Azure CLI: az ad app](https://learn.microsoft.com/en-us/cli/azure/ad/app?view=azure-cli-latest)
- [Azure CLI: permissions and admin consent](https://learn.microsoft.com/en-us/cli/azure/ad/app/permission?view=azure-cli-latest)
- [CLI for Microsoft 365: use your own Entra identity](https://pnp.github.io/cli-microsoft365/user-guide/using-own-identity/)
- [CLI for Microsoft 365: login](https://pnp.github.io/cli-microsoft365/cmd/login/)
- [CLI for Microsoft 365: spo file add](https://pnp.github.io/cli-microsoft365/cmd/spo/file/file-add/)
- [CLI for Microsoft 365: request Graph/SharePoint](https://pnp.github.io/cli-microsoft365/cmd/request/)
- [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [Microsoft Graph: get site by path](https://learn.microsoft.com/en-us/graph/api/site-getbypath)
- [Microsoft: selected permissions for SharePoint and OneDrive](https://learn.microsoft.com/en-us/graph/permissions-selected-overview)
- [CLI for Microsoft 365: publish Teams app](https://pnp.github.io/cli-microsoft365/cmd/teams/app/app-publish/)
- [Microsoft Graph: publish Teams app](https://learn.microsoft.com/en-us/graph/api/teamsapp-publish?view=graph-rest-1.0)
