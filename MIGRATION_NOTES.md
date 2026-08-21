# Migration Notes

This engine currently requires Recording Studio `~> 4.2`.

Install the engine migration after the host application's
`recording_studio_recordings` table exists:

```bash
bin/rails generate recording_studio_webhooks:migrations
bin/rails db:migrate
```

Hosts upgrading from Recording Studio 3.x must also install core's harden
indexes migration (`harden_recording_studio_indexes_and_constraints`) before
relying on 4.0 uniqueness and timeline indexes.

The generated migration creates exactly four PostgreSQL UUID tables:
endpoints, endpoint tokens, inbound events, and action attempts. It has a foreign
key to `recording_studio_recordings`, so it must run after Recording Studio's
migrations.

Endpoints are tree objects (`recording_studio_recordable`). Inbound events and
action attempts are exhaust tables, not children of the recording tree.

Do not edit a copied migration to add plaintext token, provider secret, raw
header, or raw payload columns. Use host credentials for verifier material and
the engine's safe metadata/policy fields only.


```bash
bin/rails generate recording_studio_webhooks:migrations
bin/rails db:migrate
```

The generated migration creates exactly four PostgreSQL UUID tables:
endpoints, endpoint tokens, inbound events, and action attempts. It has a foreign
key to `recording_studio_recordings`, so it must run after Recording Studio's
migrations.

Do not edit a copied migration to add plaintext token, provider secret, raw
header, or raw payload columns. Use host credentials for verifier material and
the engine's safe metadata/policy fields only.
