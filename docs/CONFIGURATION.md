# Configuration Reference

`RecordingStudioWebhooks.configure` exposes the following host-controlled
settings.

| Setting | Default | Purpose |
| --- | --- | --- |
| `dispatcher` | `:sidekiq` | `:sidekiq`, `:active_job`, or a callable |
| `queue_name` | `recording_studio_webhooks` | queue for execution jobs |
| `max_payload_bytes` | 1 MiB | maximum raw JSON request size |
| `content_types` | JSON types | accepted public request content types |
| `default_policy` | enabled, independent | base action policy |
| `secret_redaction_keys` | common secret names | additive payload filtering |
| `provenance_keys` | request metadata allowlist | fields retained with events |
| `authorization_hook` | nil | final intake authorization hook |
| `rate_limiter` | nil | intake rate-limit hook |
| `admin_authorizer` | nil | required admin authorization callback |
| `admin_recording_scope` | nil | optional Recording Studio scope callback |
| `token_digest_secret` | nil | optional HMAC key from host credentials |

Provider callbacks and intake hooks should return `true` to permit work. A
false value or exception fails closed. Signature verifiers receive request bytes
only in memory. Authorization and rate-limit hooks receive a redacted payload.

Use `provider_roots`, `action_roots`, and `automatic_discovery = true` only for
explicit, trusted local directories. Discovery loads Ruby files in lexical
order; it does not scan arbitrary constants.
