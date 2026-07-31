import { App } from '@microsoft/teams.apps';

const port = Number.parseInt(process.env.PORT ?? '3978', 10);

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('PORT must be an integer between 1 and 65535.');
}

for (const name of ['CLIENT_ID', 'CLIENT_SECRET', 'TENANT_ID']) {
  if (!process.env[name]) {
    throw new Error(`${name} is required.`);
  }
}

const app = new App();

app.on('message', async ({ activity, send }) => {
  const receivedAt = new Date().toISOString();

  console.log(
    JSON.stringify({
      event: 'msteams-echo-message-received',
      receivedAt,
      activityId: activity.id ?? null,
      conversationId: activity.conversation?.id ?? null,
      conversationType: activity.conversation?.conversationType ?? null,
      tenantId: activity.conversation?.tenantId ?? null,
      senderId: activity.from?.id ?? null,
    }),
  );

  await send({ type: 'typing' });
  await send(`ARIA Teams onboarding test passed at ${receivedAt}.`);
});

await app.start(port);
console.log(
  JSON.stringify({
    event: 'msteams-echo-ready',
    port,
    path: '/api/messages',
  }),
);
