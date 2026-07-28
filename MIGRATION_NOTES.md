# Migration Notes

Install the engine migration after the host application's
`recording_studio_recordings` table exists:

```bash
bin/rails generate recording_studio_webhooks:migrations
bin/rails db:migrate
```

The generated migration creates exactly four PostgreSQL UUID tables:
endpoints, endpoint tokens, inbound events, and action plans. It has a foreign
key to `recording_studio_recordings`, so it must run after Recording Studio's
migrations.

Do not edit a copied migration to add plaintext token, provider secret, raw
header, or raw payload columns. Use host credentials for verifier material and
the engine's safe metadata/policy fields only.
