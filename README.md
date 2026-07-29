# ARIA Microsoft Customer Onboarding Package

This package contains the customer-facing Microsoft onboarding materials for
ARIA. It covers two independent tracks:

- Microsoft 365 delegated integration for Outlook, Calendar, SharePoint, and
  OneDrive through CLI for Microsoft 365.
- Microsoft Teams channel setup for the optional ARIA Teams bot.

The tracks are independent. Running one track does not require running the
other.

## Prerequisites

All tracks require:

- a Bash-compatible shell, such as macOS, Linux, WSL, or a CI runner with Bash;
- Git, or a ZIP download of this repository;
- Node.js 20+ and npm;
- `jq`;
- a private output folder for generated handoff artifacts.

The Microsoft 365 delegated integration track also requires:

- Azure CLI (`az`);
- CLI for Microsoft 365 (`m365`) version `11.10.0`;
- a Microsoft Entra user that can create and manage App Registrations and
  Enterprise Applications in the customer Microsoft tenant;
- admin-consent authority if the script should grant tenant-wide admin consent.

For the full script path, including admin consent, sign in with a Microsoft
Entra user assigned one of these roles:

- Cloud Application Administrator;
- Application Administrator;
- Privileged Role Administrator;
- Global Administrator.

`Cloud Application Administrator` or `Application Administrator` is normally
enough for this package because it requests delegated permissions only. If the
customer separates app creation from admin consent, run the script with
`--skip-admin-consent`, then have an authorized administrator review and grant
admin consent separately.

After cloning or downloading this repository, check the workstation first:

```bash
./scripts/check-m365-prerequisites.sh
```

If the checker reports missing tools, install the missing prerequisites and run
the checker again.

For a quick manual preflight:

```bash
node --version
npm --version
jq --version
az version
m365 version
```

## Install Missing Prerequisites

If the checker reports missing tools, use the block that matches the
administrator workstation. Use the customer's approved software distribution
process if direct package-manager installation is restricted.

### Windows PowerShell

Run PowerShell as Administrator:

```powershell
winget install --exact --id Git.Git
winget install --exact --id OpenJS.NodeJS.LTS
winget install --exact --id jqlang.jq
winget install --exact --id Microsoft.AzureCLI
npm install -g @pnp/cli-microsoft365@11.10.0
```

Close and reopen the terminal after `winget` installs the tools. Run the shell
scripts from Git Bash, WSL, or another Bash-compatible shell.

### macOS

```bash
command -v brew >/dev/null 2>&1 || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew update
brew install git node jq azure-cli
npm install -g @pnp/cli-microsoft365@11.10.0
```

### Ubuntu Or WSL

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

After installation, close and reopen the terminal, then confirm:

```bash
./scripts/check-m365-prerequisites.sh
```

Before running the Microsoft 365 provisioning script, sign in to the target
customer tenant:

```bash
az login --tenant <MICROSOFT_TENANT_ID> --allow-no-subscriptions
az account show --query '{tenantId:tenantId,user:user.name}' --output json
```

The Microsoft Teams channel track also requires `unzip` and Microsoft Teams CLI
`3.0.3`, but Teams is optional and is not needed for Microsoft 365-only
onboarding.

## Quick Start

From this package directory:

```bash
./scripts/check-m365-prerequisites.sh
./scripts/provision-clim365-app.sh --help
./scripts/provision-clim365-app.sh --print-input-template
./scripts/provision-aria-msteams-bot.sh --help
```

Use the detailed guide in
`docs/microsoft-customer-onboarding.md` before running either script.

## Package Contents

| Path | Audience | Purpose |
| --- | --- | --- |
| `docs/microsoft-customer-onboarding.md` | Customer admin and ARIA operator | Full onboarding guide, ownership model, inputs, outputs, and operator settings |
| `scripts/provision-clim365-app.sh` | Customer admin | Creates or updates the Microsoft 365 delegated App Registration |
| `scripts/check-m365-prerequisites.sh` | Customer admin | Checks local tools required for Microsoft 365 delegated onboarding |
| `scripts/verify-clim365-access.sh` | Customer admin or ARIA operator | Verifies delegated CLI for Microsoft 365 access after login |
| `scripts/provision-aria-msteams-bot.sh` | Customer admin | Creates the optional Microsoft Teams app and bot package |
| `scripts/validate-msteams-handoff.sh` | Customer admin or ARIA operator | Validates Teams handoff files without printing secret values |
| `examples/microsoft-365-inputs.env.example` | Customer admin | Fillable reference for Microsoft 365 inputs |
| `examples/teams-inputs.env.example` | Customer admin and ARIA operator | Fillable reference for Teams channel inputs |
| `MANIFEST.md` | Customer admin and ARIA operator | Sendable-package inventory and produced artifacts |

## What The Customer Sends To ARIA

Microsoft 365 delegated integration produces:

- `aria-m365-integration-handoff.json`
- admin consent confirmation
- integration user access confirmation

Microsoft Teams channel setup produces:

- `aria-msteams-handoff.json`
- `aria-msteams-secret.json`
- `aria-msteams-app.zip`
- `manifest.json`
- `teams-doctor.json`

Send `aria-msteams-secret.json` only through the approved secret channel. The
Microsoft 365 handoff does not contain passwords, client secrets, access
tokens, refresh tokens, or MFA material.

## What Is Not Included

This package intentionally does not include ARIA internal runtime or AWS
Secrets Manager scripts. ARIA operators use the customer handoff artifacts to
set tenant runtime settings from the ARIA internal repository.

## Local Validation

```bash
bash -n scripts/*.sh
```

Inside the ARIA monorepo, the same check can be run with:

```bash
pnpm --filter @aria/microsoft-customer-onboarding test
```

The package test checks shell syntax for the included scripts.

## Distribution

Distribute this directory as the customer onboarding bundle. Keep generated
handoff files out of source control unless a secure repository and retention
policy have been explicitly approved.
