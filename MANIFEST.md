# Package Manifest

## Included Files

| File | Description |
| --- | --- |
| `README.md` | Package entry point and quick-start instructions |
| `docs/microsoft-customer-onboarding.md` | Complete customer onboarding guide |
| `scripts/check-m365-prerequisites.sh` | Track-aware Microsoft 365 and Teams prerequisite checker |
| `scripts/provision-clim365-app.sh` | Microsoft 365 delegated App Registration script |
| `scripts/verify-clim365-access.sh` | Microsoft 365 delegated access verifier |
| `scripts/provision-aria-msteams-bot.sh` | Optional Microsoft Teams app and bot provisioning script |
| `scripts/validate-msteams-handoff.sh` | Teams handoff validator |
| `scripts/publish-install-msteams-app.sh` | Automated organization catalog publication, Team installation, and RSC consent script |
| `scripts/verify-msteams-installation.sh` | Live Teams app, bot, catalog, installation, and RSC verifier |
| `scripts/start-msteams-echo-bot.sh` | Safe launcher for the temporary Teams SDK echo bot |
| `tools/teams-echo-bot/` | Pinned Teams SDK echo bot for live validation without OpenClaw |
| `examples/microsoft-365-inputs.env.example` | Microsoft 365 input worksheet |
| `examples/teams-inputs.env.example` | Microsoft Teams input worksheet |
| `package.json` | Local validation and help commands |
| `.gitignore` | Prevents generated handoff outputs from being committed accidentally |

## Excluded Internal Files

The following ARIA internal scripts are not included in this customer package:

- `scripts/seed-tenant-clim365-secrets.sh`
- `scripts/seed-tenant-msteams-secrets.sh`
- gateway deployment, runtime reload, ECS, and AWS helper scripts

ARIA operators run those internal scripts only after receiving the customer's
handoff artifacts through the approved channel.

## Produced Customer Artifacts

Microsoft 365 delegated integration:

- `aria-m365-integration-handoff.json`

Microsoft Teams channel:

- `aria-msteams-handoff.json`
- `aria-msteams-secret.json`
- `aria-msteams-app.zip`
- `manifest.json`
- `teams-doctor.json`
- `aria-msteams-installation.json` after automated catalog publication and Team installation
- `aria-msteams-live-verification.json` after live catalog and Team checks

## Security Boundary

The Microsoft 365 track uses delegated device-code authentication and creates
no client secret. The Teams track creates a bot client secret, which must be
shared only through the approved secret channel.
