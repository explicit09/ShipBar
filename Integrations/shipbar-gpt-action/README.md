# ShipBar Private GPT Action

This package connects a private Custom GPT to the hosted ShipBar relay without OpenAI Platform model calls.

## Configure

1. In ChatGPT web, create a private GPT and paste `instructions.md` into Instructions.
2. Add an Action and import `openapi.yaml`, which is already pointed at the dedicated ShipBar Relay project.
3. Set Authentication to **API key**, **Custom header**, header name `X-ShipBar-Key`, and enter the generated relay key from macOS Keychain service `com.shipbar.relay`. Do not use an OpenAI API key.
4. Keep the GPT private. Test capture, search, device listing, and status in Preview before using it on mobile.

ChatGPT mobile can use a GPT created on web. The API key is stored in the GPT Action configuration; it must never be pasted into prompts, source files, or screenshots.

## Rotate or revoke

Generate a new high-entropy relay key, update the stored hash in the Supabase secret/configuration, redeploy, and replace the Action key. Deleting the Action or rotating the key revokes access.

## Verify

```bash
deno test --allow-read Integrations/shipbar-gpt-action/test/openapi_test.ts
```

The internal `/sync/pull` and `/sync/push` routes intentionally do not appear in the Action schema.
