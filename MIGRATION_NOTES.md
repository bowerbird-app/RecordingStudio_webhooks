# Migration Notes

This engine requires Recording Studio `>= 6.3.0` and Flatpack `>= 0.1.341`.

## 0.8.0

Hosts must run the engine migrations.

```bash
bin/rails generate recording_studio_webhooks:migrations
bin/rails db:migrate
```

`RemovePlaintextTokenFromEndpointTokens` drops the `token` column when it
exists. Digest is already `NOT NULL`, so the migration does not backfill.
Down adds an empty `token` column; plaintext cannot be restored from a
digest.

New installs get the four tables without a `token` column. The drop
migration is a no-op when that column is already gone.

Point providers at `POST /<mount>/inbound` with
`Authorization: Bearer` or `X-Recording-Studio-Webhook-Token`. Build that
URL with `recording_studio_webhooks_inbound_header_path`.
`recording_studio_webhooks_inbound_path(endpoint_token:)` still names the
path-token route. That route is deprecated: tokens in URLs end up in
server logs. Previously issued `/inbound/:endpoint_token` URLs still
authenticate.

Pin Recording Studio `v6.3.0` and Metrics `v0.7.2`. Admin stays `v2.5.1`.
This gem no longer ships a Bundler `Gem::Specification` prepend to widen
`recording_studio` requirements.

Engine `ApplicationController` includes `RecordingStudio::ControllerLayout`.
`config.layout = nil` keeps core's Default Layout.

## 0.7.2

No database migration.

Admin date-range filters pass `preset_name:` to
`FlatPack::DateRangeInput::Component`. FlatPack Apply writes the preset key and
dispatches bubbling `change` events, then `flat-pack--flatpack-date-picker:apply`.
Do not keep a host Apply click handler next to those events. Reload kit
JavaScript. Development Gemfiles pin Flatpack tag `v0.1.341`.

## 0.7.0

No database migration. The generated migration still creates exactly four
PostgreSQL UUID tables.

`config.layout` defaults to `nil`. `nil` uses the host Recording Studio
layout, then `recording_studio/default_layout`. `false` renders with no
layout. A String is a layout name. A callable must accept `controller:` and
return a String, `nil`, or `false`.

```ruby
RecordingStudioWebhooks.configure do |config|
  config.layout = nil
end
```

Engine controllers call `recording_studio_layout`. Do not include
`RecordingStudio::UsesDefaultLayout` and do not set
`layout "recording_studio/default_layout"`.

Page headings belong in `content_for :title` and `content_for :subtitle`.
Back and close belong in `flat_pack_page_nav`. Right-side actions belong in
`register_page_nav` or `recording_studio_page_nav_right`.

Development Gemfiles pin Recording Studio `v6.1.0` and Flatpack tag
`v0.1.331`. Accessible `v0.21.0`, Metrics `v0.6.1`, Admin `v2.5.1`, Root
Switchable `v0.11.0`, Cache `v0.5.1`, and Trashable `v0.11.3` still
declare `recording_studio` below 5.
`test/support/widen_recording_studio_requirement.rb` relaxes that
requirement before Bundler setup so this repository can boot. Dummy and
engine Cards use Flatpack `background`, `border`, `shadow`, and the rest
of the Card keywords. Do not pass `style:` to `FlatPack::Card`.

## Earlier notes

Hosts on Recording Studio 4.2 used the notes below. 0.7.0 replaces that
requirement.

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

