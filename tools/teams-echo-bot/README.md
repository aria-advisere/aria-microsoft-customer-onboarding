# Microsoft Teams Onboarding Echo Bot

This temporary bot validates the live Microsoft Teams messaging path without
requiring an ARIA/OpenClaw runtime. It uses Microsoft Teams SDK and replies to
each received message with a timestamped success message.

Do not use this tool as a production bot. Stop it and revoke the temporary
tunnel after the onboarding test.

From the package root:

```bash
cd tools/teams-echo-bot
npm ci
cd ../..

./scripts/start-msteams-echo-bot.sh \
  --secret-json ./aria-example-microsoft/aria-msteams-secret.json \
  --port 3978
```

The bot listens on `/api/messages`. Expose the port through a customer-approved
HTTPS tunnel and use the resulting URL plus `/api/messages` as the provisioning
script's `--endpoint` value.

The bot logs activity, conversation, tenant, and sender identifiers. It does
not log message text or credentials.
