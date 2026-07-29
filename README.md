# ARIA Microsoft Customer Onboarding Package

This package contains the customer-facing Microsoft onboarding materials for
ARIA. It covers two independent tracks:

- Microsoft 365 delegated integration for Outlook, Calendar, SharePoint, and
  OneDrive through CLI for Microsoft 365.
- Microsoft Teams channel setup for the optional ARIA Teams bot.

The tracks are independent. Running one track does not require running the
other.

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
