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

## 0.6.6

No migration. Action attempts charts ignore nil `completed_at`. Engine admin
pages use the Admin engine's Webhooks section path instead of a host
`recording_studio_admin_webhooks_path`.

## 0.6.5

No migration. Runtime `recording_studio_metrics` is `>= 0.3.0, < 0.6`. Dummy
and development pin git tag `v0.5.0`.

## 0.6.4

No migration. Action attempts `stuck=1` uses the same `Metrics::STUCK` rule as
the Stuck retries card and skips the `completed_at` window. The Event status
card is gone; `webhook_events.by_status` is unchanged.

## 0.6.3

No migration. The Admin Webhooks section now links Providers, Endpoints, and
Actions as well as Webhook traffic, Action attempts, and Tokens, so those
screens are enabled on hosts that list sections on the Admin root. The Action
attempts hub card and screen both count `completed_at` in Admin `last_4_weeks`.
The Action attempts chart applies the status filter.

## 0.6.2

No migration. Admin Webhooks hub cards read `webhook_attempts.stuck`,
`webhook_attempts.oldest_stuck_age`, `webhook_attempts.failed_over_time`, and
`webhook_events.by_status`. The Admin Webhooks section links Action attempts
so that screen is enabled on hosts that list sections on the Admin root.
Failed attempts and Action attempts (`status=failed`) both use the current
root, `completed_at`, and Admin `last_4_weeks`. Webhook traffic puts status,
provider, and endpoint in the filter modal. Admin stays optional and is not a
gemspec dependency.

## 0.6.1

No migration. Pin `recording_studio_metrics` to `>= 0.3.0, < 0.4`. MCP 0.17.0
lists one tool per registered metric. Timeseries tools take `from`, `to`, and
`interval`. Other webhook metrics do not.

## 0.6.0

No migration. Adds `webhook_attempts.failed_over_time` and `webhook_events.by_status`.

