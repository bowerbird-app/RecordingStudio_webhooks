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

The admin interface is under `/admin` inside the engine mount. See
[docs/admin-webhooks-hierarchy.txt](docs/admin-webhooks-hierarchy.txt).
It provides:

- Recording-scoped endpoints;
- current/rotated/revoked token history;
- redacted events and their action attempts/attempt history; and
- a sandbox that matches and redacts a manually supplied sample without
  persisting the sample or executing an action.

The UI uses FlatPack components. Token issuance renders a no-store,
one-response page instead of a flash or redirect. Close links on those
engine pages use the RecordingStudio Admin engine's Webhooks section path
(`section_path("admin_webhooks")` on the Admin mount, or
`/admin/sections/admin_webhooks` when Admin is at the default mount). They
do not call a host helper named `recording_studio_admin_webhooks_path`.

When RecordingStudio Admin is loaded, the Admin Webhooks hub shows metric
cards that call `RecordingStudioMetrics::Admin.execute` (site scope). Stuck
retries uses `webhook_attempts.stuck` (count plus a bar chart grouped by
`action_name`) and `webhook_attempts.oldest_stuck_age`, and links to Action
attempts with `stuck=1`. That filter is the same `Metrics::STUCK` rule and
skips the default `completed_at` window so overdue retries still appear.
The section lists Webhook traffic, Providers, Endpoints, Actions,
Action attempts, and Tokens so those screens are enabled when the host
restricts Admin to named sections. Failed attempts uses
`webhook_attempts.failed_over_time` (week buckets on `completed_at`, current
root, Admin `last_4_weeks`) and links to Action attempts with `status=failed`.
That screen filters the same window on `completed_at`. The Action attempts
card uses that same `completed_at` window. The Action attempts chart buckets
finished attempts on `completed_at` and omits rows where that column is
blank, so pending and retrying attempts do not crash the series. Webhook traffic
filters status, provider, and endpoint in the filter modal.

## Metrics

`RecordingStudioWebhooks::Metrics.register!` registers site-wide metrics with
RecordingStudio Metrics (`>= 0.3.0, < 0.6`) at boot. Every metric uses
`blast_radius: :site`, is exposed on the `:operations` API only, and is visible
over the API only to actors with `:view` on the Admin root
(`Api::Access.can_view?`). This gem does not call
`RecordingStudioMetrics::Api.register!`. When RecordingStudio API is present,
the host registers Metrics endpoints once:

```ruby
RecordingStudioMetrics::Api.register!(api: :operations)
```

RecordingStudio MCP `0.17.0` lists one read-only tool per exposed metric. The
tool name is the identifier with its one dot replaced by a hyphen. Only
timeseries tools take `from`, `to`, and `interval`. `start` and `start_at` are
the same as `from`. `end` and `end_at` are the same as `to`. Counts, breakdowns,
and the oldest-stuck-age scalar do not take a date window.

| Metric | MCP tool | Type | Unit | Window | `group_by` | Filters |
| --- | --- | --- | --- | --- | --- | --- |
| `webhook_events.over_time` | `webhook_events-over_time` | time series on `received_at` | count | `from`, `to`, `interval` | none | none |
| `webhook_events.by_provider` | `webhook_events-by_provider` | breakdown on `provider_name` | count | none | not supported | none |
| `webhook_events.by_status` | `webhook_events-by_status` | breakdown on `status` | count | none | not supported | `provider_name`, `endpoint_id`, `event_type` (Events screen names) |
| `webhook_attempts.by_status` | `webhook_attempts-by_status` | breakdown on `status` | count | none | not supported | none |
| `webhook_attempts.failed_over_time` | `webhook_attempts-failed_over_time` | time series on `completed_at`, `status = failed` | count | `from`, `to`, `interval` | `action_name` | `provider`, `endpoint`, `action_name`, `event_id` |
| `webhook_attempts.stuck` | `webhook_attempts-stuck` | count | count | none | `action_name` | `provider`, `endpoint`, `action_name`, `event_id` |
| `webhook_attempts.oldest_stuck_age` | `webhook_attempts-oldest_stuck_age` | custom scalar | seconds | none | not supported | `provider`, `endpoint`, `action_name`, `event_id` |
| `webhook_endpoints.enabled` | `webhook_endpoints-enabled` | count | count | none | none | none |

### Stuck retries

An attempt is **retry due** when `ActionAttempt.due` selects it: status
`pending` or `retrying` and `next_attempt_at` is null or at/before now. Only
retries carry a schedule (`fail_and_schedule_retry!` and
`schedule_dispatch_retry!` set `retrying` with `next_attempt_at`; claiming or
queueing clears it), so a **pending retry** is a `pending`/`retrying` attempt
with a non-null `next_attempt_at`.

`webhook_attempts.stuck` counts pending retries that are still due at
`now - grace`, i.e. `next_attempt_at <= now - 300 seconds`. The grace period
(`Metrics::STUCK_RETRY_GRACE`) is the default policy `max_retry_backoff`
(300 seconds), the longest delay the gem schedules between attempts under
default policy. An attempt past that point has missed both its own dispatch
(`wait_until: next_attempt_at`) and has had a full backoff window for a
scheduled `dispatch_due` run to pick it up. Endpoints that override
`max_retry_backoff` still use the 300 second grace.

`webhook_attempts.oldest_stuck_age` is the number of whole seconds since the
earliest `next_attempt_at` among the same stuck attempts (`null` when nothing
is stuck). It is one `MIN(next_attempt_at)` over the
`(status, next_attempt_at)` index.

Both are point-in-time values for "now", so they take no `from`, `to`, or
`interval`. `group_by: action_name` follows RecordingStudio Metrics
`min_group_size` (default 5): smaller groups are folded into `other`.
Attempts do not store an endpoint or event type column, so neither is
offered as a `group_by`; use the `endpoint` filter instead. Filters use the
names and matching rules of the Admin "Action attempts" screen: `provider`
(inbound event provider name), `endpoint` (endpoint label), `action_name`
(`all` means no filter), and `event_id` (inbound event id).

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

`test/dummy` mounts the engine at `/webhooks` and seeds a stable Recording Studio
recording plus a demo endpoint for local browsing. `rake test:dummy` loads schema
without those seeds so Admin screens query the workspace each test creates.
Tests use a no-op dispatcher so CI can run without Redis; development uses
Sidekiq. Sign in as `admin@admin.com` with password `Password`, then open
**Webhook endpoints** from Admin webhooks. The demo never sends outbound requests.

The dummy is on the Recording Studio 6.1 kit from `Gemfile`, `test/dummy/Gemfile`,
and `recording_studio_webhooks.gemspec`: core tag `v6.1.0` (runtime `>= 6.1.0`),
Accessible tag `v0.11.1`, Root Switchable tag `v0.5.3` (lockfile `0.5.1`),
Metrics tag `v0.5.0` (runtime `>= 0.3.0`, `< 1.0`), Flatpack ref
`1fcbafe94f8eb118f0a22182f63f5110fcc97a56` (`0.1.319`, runtime `>= 0.1.315`),
and Admin git branch `cursor/rs41-accessible-06-upgrade-eb59` (lockfile `2.0.0`).
Dummy Rails is `~> 8.1.1`; the gemspec is `rails ~> 8.1.0`, `sidekiq ~> 8.1.6`,
and `view_component >= 4.14, < 5`. Authenticated dummy screens use
Recording Studio's shared default layout. `config.layout` overrides it. Flatpack
stylesheets load before Tailwind. Dummy Accessible setup uses string roles and
Accessible `0.8`–`0.11` migrations. Sibling gems that still require
`recording_studio` below 5 are widened in `test/support/widen_recording_studio_requirement.rb`.

Controller flashes and form errors resolve under `recording_studio.webhooks.*`
with English `default:` on every lookup. Hosts override by defining the same
keys in their own `config/locales`. Admin DSL titles, column headers, cell
values, model validation messages, and raised routing errors stay English
literals.

Dummy credentials (`test/dummy/config/credentials.yml.enc`) are encrypted with the shared RecordingStudio_* development master key. Set `RAILS_MASTER_KEY` or put that key in `test/dummy/config/master.key` (gitignored). Keep the encrypted file; do not generate a per-repo dummy key.

## Cloud Agent boot

Cloud Agent Builds run `.cursor/install.sh`, then `.cursor/fetch-skills.sh`.
The install hook provisions a cold image. On a warm snapshot it skips apt,
ruby-build, db:prepare, and tailwind when Ruby, bundle, and Postgres are
already usable. If `RAILS_MASTER_KEY` is set, it writes gitignored
`test/dummy/config/master.key` so dummy credentials decrypt. Fetch-skills always
runs last. `.cursor/start.sh` starts PostgreSQL on each boot. Rebuild with Draft
off to load a new pack. See
[Cursor skills in Cloud Agents](docs/cursor-skills.md).
