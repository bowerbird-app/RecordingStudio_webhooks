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
| `admin_authorizer` | nil | decides which users can access the webhooks admin UI |
| `admin_recording_scope` | nil | decides which recordings those users can view and manage |
| `token_digest_secret` | nil | optional HMAC key from host credentials |
| `layout` | `nil` | `nil`, `false`, a layout name, or `->(controller:) { ... }` |

Provider callbacks and intake hooks should return `true` to permit work. A
false value or exception fails closed. Signature verifiers receive request bytes
only in memory. Authorization and rate-limit hooks receive a redacted payload.

Host apps should set `token_digest_secret` from encrypted credentials (see
`recording_studio_webhooks.token_digest_secret` in the dummy credentials file)
or another secret store. Never commit the value.

`layout` is read by `recording_studio_layout` on the engine base controller.
`nil` leaves the choice to Recording Studio. `false` skips the layout. A
callable is invoked as `call(controller:)` and must return a String, `nil`,
or `false`. Any other value raises `ArgumentError`.

## Copy and locales

Non-view admin flashes and form errors live under
`recording_studio.webhooks.flashes.*` and
`recording_studio.webhooks.form_errors.*` in the gem's `config/locales/en.yml`.
Lookups go through `RecordingStudioWebhooks::Copy.t` and always pass an English
`default:`. Hosts override by defining the same nested keys in their own
`config/locales`. Admin DSL screen titles, subtitles, column headers, and cell
values stay English string literals (they are captured at class load). Model
validation messages and raised routing errors stay English too.

Use `provider_roots`, `action_roots`, and `automatic_discovery = true` only for
explicit, trusted local directories. Discovery loads Ruby files in lexical
order; it does not scan arbitrary constants. Ignore those directories from
Zeitwerk so Rails 8 CI eager load does not treat `app/webhooks` as an autoload
root.
