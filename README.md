# RecordingStudio Webhooks

`recording_studio_webhooks` is a mountable, **inbound-only** Rails engine for
accepting provider events that belong to stable `RecordingStudio::Recording`
records. It validates and redacts intake data, persists immutable planning
snapshots, and executes registered local actions through Sidekiq, Active Job,
or a host-supplied dispatcher.

It does not send outgoing webhooks, proxy requests, retain provider signing
secrets, retain secret-store locations, or persist plaintext endpoint tokens.

## Install

Add the engine and your Recording Studio dependency to the host application,
then install the engine:

```bash
bundle add recording_studio_webhooks
bin/rails generate recording_studio_webhooks:install
bin/rails db:migrate
```

The install generator creates an initializer, mounts the engine at
`/recording_studio_webhooks`, and generates one migration containing the four
engine tables. Use `--mount-path=/webhooks` to choose another safe lowercase
path, or `--skip-migrations` when migrations are managed separately.

Sidekiq is the default dispatcher. The engine requires Sidekiq `~> 8.1.6`;
that version was checked against the GitHub advisory database when this engine
was added. Hosts using another queue adapter can configure Active Job or a
custom dispatcher instead. The engine's FlatPack admin views expect FlatPack
to be supplied by the Recording Studio host UI bundle.

## Minimal configuration

Administration is intentionally denied until the host opts in:

```ruby
# config/initializers/recording_studio_webhooks.rb
RecordingStudioWebhooks.configure do |config|
  config.admin_authorizer = ->(context) { context.actor&.admin? }
  config.admin_recording_scope = ->(_context) { RecordingStudio::Recording.all }

  # Recommended: source this from encrypted credentials. It is never reported
  # or snapshotted. Random tokens remain safely hashed if this is unset.
  config.token_digest_secret = Rails.application.credentials.dig(
    :recording_studio_webhooks, :token_digest_secret
  )

  # Optional: shorten/lengthen generated endpoint tokens.
  # Default is 18 bytes (about 24 URL-safe chars after rswh_ prefix).
  config.endpoint_token_bytesize = 18

  config.provider "billing" do |provider|
    provider.event_type ->(payload) { payload.fetch("type") }
    provider.event_id ->(payload) { payload["id"] }
  end

  config.action "billing.invoice_paid",
    ->(context) { InvoicePaidHandler.call(context) },
    provider: "billing",
    event: "invoice.paid",
    policy: { max_retries: 2 }
end
```

`admin_authorizer` is where your app decides who is allowed into the webhooks
admin area.
`admin_recording_scope` is where your app decides which recordings that allowed
user can see and manage.
An absent authorizer always returns a generic not-found response.

## Provider and action registration

Provider and action names are normalized to lowercase and duplicate names are
rejected. Registry iteration is lexical and matching ties are deterministic.
Providers may register a signature verifier, event type extractor, event ID
extractor, and provider policy.

Action patterns are deliberately limited:

| Pattern | Matches |
| --- | --- |
| `invoice.paid` | exactly `invoice.paid` |
| `invoice.*` | `invoice.paid` and `invoice.payment.failed` |

Only a final `.*` is supported. General globs and prefix wildcards are
rejected. Exact patterns win, then longer wildcard prefixes, then action
priority and lexical action name.

For explicit file discovery, configure absolute provider/action roots and set
`automatic_discovery = true`. Files are required in lexical order; the engine
never infers constants from paths.

## Policies

Every intake and action attempt receives an immutable policy snapshot. Precedence
is, from highest to lowest:

1. endpoint override;
2. action policy;
3. provider policy;
4. global `default_policy`.

Supported policy keys are `enabled`, `execution_mode` (`independent` or
`sequential`), `max_retries`, `retry_backoff`, `max_retry_backoff`,
`redaction_keys`, and `deduplicate`. Required redaction keys are always
additive and cannot be removed by a lower-level policy.

## Public intake

With the default mount, providers POST JSON to:

```text
POST /recording_studio_webhooks/inbound/:endpoint_token
Authorization header: endpoint credential
Content-Type: application/json
```

`X-Recording-Studio-Webhook-Token` is also supported for providers that
cannot send an Authorization header. Query-string tokens are intentionally unsupported.
The public controller is stateless and does not use browser sessions; all
administrative endpoints retain Rails CSRF protection. It returns only a
generic JSON status: `accepted`, `duplicate`, `unauthorized`, `not_found`,
`invalid`, or `unavailable`.

The intake service:

- performs current-token lookup with a constant-time digest comparison;
- enforces content type and payload-size limits;
- invokes an optional provider signature verifier in memory;
- invokes optional rate-limit and authorization hooks with redacted data;
- canonicalizes payloads for race-safe deduplication;
- persists only a redacted payload and an allowlisted provenance subset; and
- creates immutable endpoint, token, policy, and action snapshots before
  anything is dispatched.

Configure `max_payload_bytes`, `content_types`, `secret_redaction_keys`, and
`provenance_keys` to meet host requirements. Secret-looking keys such as
`token`, `authorization`, `password`, and `signature` are filtered even if
they are not listed explicitly.

## Data model

The engine owns exactly four UUID-primary-key tables:

1. `recording_studio_webhooks_endpoints`;
2. `recording_studio_webhooks_endpoint_tokens`;
3. `recording_studio_webhooks_inbound_events`; and
4. `recording_studio_webhooks_action_attempts`.

Endpoints reference `recording_studio_recordings`, not a mutable host
recordable. Endpoint identity and recording linkage are immutable after
creation. Token records contain only a digest, short prefix, lifecycle times,
and safe metadata. Inbound events and action attempts hold immutable JSON
snapshots. Attempt state is append-only JSON history on the attempt so the engine
keeps the four-table boundary.

Issuing or rotating a token revokes every previous unrevoked token under a row
lock. The resulting plaintext is available from the issuance object exactly
once and is never serialized, logged, or stored.

## Execution and retries

Action attempts store action name, execution position, policy, sanitized errors,
and attempts. Independent attempts can run independently. Sequential attempts wait
for preceding sequential attempts to reach a terminal state. Failed handlers use
bounded exponential backoff and are retried only up to their policy limit.

The default dispatcher pushes only an action-attempt UUID to Sidekiq. To use a
different dispatcher:

```ruby
RecordingStudioWebhooks.configure do |config|
  config.dispatcher = :active_job

  # Or receive only a attempt ID and optional schedule:
  # config.dispatcher = ->(attempt_id, wait_until = nil) { MyQueue.push(attempt_id, wait_until) }
end
```

Actions receive an immutable context containing the action attempt, inbound event,
endpoint, redacted payload, and safe provenance. They never receive an
endpoint token or a provider secret.

## Admin hierarchy and sandbox

The admin interface is under `/admin` inside the engine mount. It provides:

- Recording-scoped endpoints;
- current/rotated/revoked token history;
- redacted events and their action attempts/attempt history; and
- a sandbox that matches and redacts a manually supplied sample without
  persisting the sample or executing an action.

The UI uses FlatPack components. Token issuance renders a no-store,
one-response page instead of a flash or redirect.

## Operations

```bash
bin/rails recording_studio_webhooks:status
bin/rails recording_studio_webhooks:doctor
bin/rails recording_studio_webhooks:dispatch_due
```

`status` emits a non-secret configuration/table report. `doctor` checks
Recording Studio availability, explicit admin authorization, registry setup,
all four tables, and Sidekiq availability when it is the selected dispatcher.
Schedule `dispatch_due` to reconcile temporary queue failures and process
crashes after a attempt is persisted but before it is enqueued.

See [configuration](docs/CONFIGURATION.md),
[architecture](docs/ARCHITECTURE.md), [operations](docs/OPERATIONS.md), and
[security](docs/SECURITY.md) for detail.

## Dummy application

`test/dummy` mounts the engine at `/webhooks`, seeds a stable Recording Studio
recording plus a demo endpoint, and configures a no-op dispatcher. Sign in as
`admin@admin.com` with password `Password`, then use **Webhook endpoints** in
the sidebar. The demo never sends outbound requests or executes queued work.
