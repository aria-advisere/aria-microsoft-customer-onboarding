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
- permission to create App Registrations and Enterprise Applications in the
  customer Microsoft tenant;
- Global Administrator, or equivalent consent authority, if the script should
  grant admin consent.

Install and preflight the Microsoft 365 tools:

```bash
node --version
npm --version
jq --version
az version
npm install -g @pnp/cli-microsoft365@11.10.0
m365 version
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
