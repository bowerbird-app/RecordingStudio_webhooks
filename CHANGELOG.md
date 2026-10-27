# Changelog

## Unreleased

## [0.7.0] - 2026-10-27

Admin pages use Recording Studio 6.1's shared layout. The host chooses that
layout with `config.layout`.

### Changed

- `recording_studio` is `>= 6.1.0`. Development pins tag `v6.1.0`.
- `flat_pack` is `>= 0.1.315`. Development pins ref `1fcbafe94f8eb118f0a22182f63f5110fcc97a56` (`0.1.319`).
- `view_component` is `>= 4.14, < 5`.
- `RecordingStudioWebhooks.configuration.layout` accepts `nil`, `false`, a layout name, or a keyword callable.
- Engine and dummy controllers call `recording_studio_layout` instead of `RecordingStudio::UsesDefaultLayout`.
- Admin views set `content_for :title` and `:subtitle`, `flat_pack_page_nav`, and `register_page_nav`.
- Cards use `background`, `border`, and `shadow`. Layouts load Flatpack stylesheets before Tailwind.

### Upgrade notes

- Bump to `0.7.0`. No database migration. The four webhook tables are unchanged.
- Set `config.layout = nil` to keep the shared default layout. Set a layout name, `false`, or `->(controller:) { ... }` to override it.
- Remove `include RecordingStudio::UsesDefaultLayout` and `layout "recording_studio/default_layout"` from host controllers. Call `recording_studio_layout`.
- Replace `recording_studio_page_nav` and `FlatPack::PageNav::Component.new(back_href:)` with `flat_pack_page_nav` and `register_page_nav`. Put the page heading in `content_for :title`.
- Sibling gems that still declare `recording_studio ~> 4.x` do not resolve next to `6.1.0`. This repository widens those requirements in `test/support/widen_recording_studio_requirement.rb` before Bundler setup. Hosts should move those gems forward, or load the same widen helper before `Bundler.setup`.

## [0.6.7] - 2026-10-22

Runtime Metrics range is now `>= 0.3.0, < 1.0` (CI tested with 0.5.0). No code change.

### Changed

- Runtime dependency `recording_studio_metrics` is `>= 0.3.0, < 1.0`.
- `.ruby-version` is `3.3.12` so CI can install Ruby on ubuntu-26.04.

### Upgrade notes

- Bump to `0.6.7`. No migration.
- No code change.

## [0.6.6] - 2026-10-20

Admin Action attempts chart and engine admin pages no longer 500.

### Fixed

- Action attempts chart skips attempts with a blank `completed_at` (pending,
  retrying, queued, running). Finished-attempt counts are unchanged.
- Engine pages under the webhooks mount close to the Admin Webhooks section
  through the Admin engine helper, not a host
  `recording_studio_admin_webhooks_path`.

### Upgrade notes

- Bump to `0.6.6`. No migration.
- Hosts that mount Admin as `:admin` (not `:webhooks`) can open the engine's
  own pages without defining `recording_studio_admin_webhooks_path`.

## [0.6.5] - 2026-10-20

Runtime Metrics range now includes 0.5.x.

### Changed

- Runtime dependency `recording_studio_metrics` is `>= 0.3.0, < 0.6`.
- Dummy and development pin git tag `v0.5.0`.

### Upgrade notes

- Bump to `0.6.5`. No migration.
- Hosts on Metrics 0.3.x stay valid. Hosts can move to Metrics `0.5.0`.
- Admin chart callers that still index `[date, value]` pairs must read `x` and
  `y` (Metrics 0.5.0). This gem already emits `{ x:, y: }`.

## [0.6.4] - 2026-10-20

Admin Webhooks Stuck retries opens Action attempts with the same stuck set.

### Added

- Action attempts accepts `stuck=1`. That uses `Metrics::STUCK` (the Stuck retries
  card's rule). The default `completed_at` window is skipped so overdue retries
  still show.

### Changed

- The Stuck retries card's More link opens Action attempts with `stuck=1`.

### Removed

- Event status card (`widgets.admin_webhooks.event_status`). The
  `webhook_events.by_status` metric is unchanged.

### Upgrade notes

- Bump to `0.6.4`. No migration.
- Staff who used the Event status card should open Webhook traffic and filter
  by status. The metric is still on the operations API and MCP.

## [0.6.3] - 2026-10-20

Admin Webhooks section links include every screen the hub widgets open.

### Changed

- The Admin Webhooks section lists Providers, Endpoints, and Actions alongside
  Webhook traffic, Action attempts, and Tokens. RecordingStudio Admin enables
  those screens wherever the section is enabled, including hosts that turn the
  section on for the Admin root.
- The Action attempts hub card counts `completed_at` over Admin `last_4_weeks`,
  the same set as `/admin/screens/action_attempts`.
- The Action attempts chart keeps the status filter when it buckets by
  `completed_at`, so `status=failed` changes the chart as well as the table.

### Upgrade notes

- Bump to `0.6.3`. No migration.
- Hosts that already enable `admin_webhooks` get the extra screens. No host
  config change.

## [0.6.2] - 2026-10-19

Admin Webhooks hub cards now read registered RecordingStudio Metrics.

### Added

- Stuck retries card (`webhook_attempts.stuck`) with a count, a bar chart by
  action, and oldest wait (`webhook_attempts.oldest_stuck_age`). Links to
  Action attempts. The Admin Webhooks section links that screen so hosts that
  enable sections on the Admin root can open it.
- Event status list (`webhook_events.by_status`). Links to Webhook traffic.

### Changed

- Failed attempts chart (`widgets.admin_webhooks.action_errors`) uses
  `webhook_attempts.failed_over_time` bucketed on `completed_at`, scoped to the
  current root, over Admin `last_4_weeks`. Action attempts uses the same
  `completed_at` window so the card and `status=failed` screen match.
- Webhook traffic keeps date range and group-by inline. Status, provider, and
  endpoint sit in the filter modal.

### Upgrade notes

- Bump to `0.6.2`. No migration.
- Admin stays optional. Hosts without `recording_studio_admin` skip the cards.

## [0.6.1] - 2026-10-16

MCP 0.17.0 lists one tool per metric this gem already registers.

### Changed

- Runtime dependency `recording_studio_metrics` is `>= 0.3.0, < 0.4`.
- README Metrics names each MCP tool (the identifier's one dot becomes a hyphen)
  and says `from` / `to` / `interval` apply only to timeseries metrics.

### Upgrade notes

- Bump to `0.6.1`. No migration.
- Pin `recording_studio_metrics` to `>= 0.3.0, < 0.4` (git tag `v0.3.1`).
- This gem still does not call `RecordingStudioMetrics::Api.register!`. When
  RecordingStudio API is present, the host still registers Metrics endpoints
  once with `RecordingStudioMetrics::Api.register!(api: :operations)`.

## [0.6.0] - 2026-10-14

### Added

- `webhook_attempts.failed_over_time`: time series of attempts that ended in
  `failed`, bucketed by `completed_at`. Unit `count`. Takes `from` / `to` /
  `interval`, `group_by=action_name` (groups under `min_group_size` 5 fold into
  `other`), and the Action attempts screen filters `provider`, `endpoint`,
  `action_name`, `event_id`.
- `webhook_events.by_status`: inbound events per status (`accepted`,
  `planned`). Unit `count`. Takes the Events screen filters `provider_name`,
  `endpoint_id`, `event_type`. A breakdown, so no date window or `group_by`.
- Both use the same site scope, `:operations` exposure, and Admin root `:view`
  check as the Events and Action attempts screens. No migration.

## [0.5.1] - 2026-10-14

Site-wide metrics deny access when the admin root resolver raises.

### Fixed

- `RecordingStudioWebhooks::Api::Access.can_view?` returns false when the admin
  root resolver raises. Recording Studio Metrics discovery no longer fails the
  request with that error.

### Upgrade notes

- Bump to `0.5.1`. No migration and no configuration change.

## [0.5.0] - 2026-10-14

### Added

- `webhook_attempts.stuck` (count, unit `count`): attempts that
  `ActionAttempt.due(now - 300.seconds)` still selects and that have a
  `next_attempt_at`, i.e. scheduled retries at least 300 seconds overdue.
  The grace is `RecordingStudioWebhooks::Metrics::STUCK_RETRY_GRACE`, the
  default policy `max_retry_backoff`. Supports `group_by: action_name`
  (RecordingStudio Metrics `min_group_size` applies).
- `webhook_attempts.oldest_stuck_age` (custom scalar, unit `seconds`): whole
  seconds since the earliest `next_attempt_at` among stuck attempts, `null`
  when none.
- Both take the Admin "Action attempts" filter names: `provider`, `endpoint`,
  `action_name`, and `event_id`. Same site scope, `:operations` exposure, and
  `Api::Access.can_view?` check as the existing webhook metrics.
- README "Metrics" section documenting every webhook metric.

### Changed

- Runtime dependency `recording_studio_metrics` `~> 0.3` (GitHub tag `v0.3.1`;
  the gem reports version `0.3.0`) for `group_by`.

### Upgrade notes

- Bump to `0.5.0`. No migration.
- Pin `recording_studio_metrics` to tag `v0.3.1`.

## [0.4.0] - 2026-10-12

### Added

- English Rails I18n keys for non-view copy under `recording_studio.webhooks`
  (controller flashes and form errors). Every lookup passes an English
  `default:` so a host locale with no fallback never shows "translation missing".
- Host English override coverage: test-only fixture
  `test/dummy/test/locales/webhooks_host_override.en.yml` loaded via
  `I18n.backend.load_translations` (no `I18n.load_path` mutation) plus a
  real-page revoke flash assert.
- Always-loaded boot-order guard
  `test/dummy/config/locales/recording_studio_webhooks_host.en.yml` for the
  rarely shown `form_errors.choose_registered_provider` key, with a render
  assert on the bad-provider create path.
- Locale regression: every `lib/**/*.rb` file must not mention
  `i18n.load_path` / `I18n.load_path`.
- Render-level asserts for endpoint create, token issue, and token revoke
  English flashes.

### Changed

- Admin controller flashes and form errors resolve through
  `RecordingStudioWebhooks::Copy.t` with English `default:`.

### Upgrade notes

- Bump to `0.4.0`. No migration.
- English hosts need no change. Copy new `recording_studio.webhooks.flashes.*`
  and `form_errors.*` keys into host locale files when translating.
- Hosts override by defining the same nested keys in their own
  `config/locales`. Public constants, model validation messages, Admin DSL
  titles/subtitles/column headers, Admin cell values, raised routing errors,
  and sandbox check result hashes stay main's literal English; translate only
  at controller/view render sites.

## [0.3.0] - 2026-10-09

Site-wide Webhooks metrics register with Recording Studio Metrics for the operations API.

### Added

- `RecordingStudioWebhooks::Metrics.register!` registers `:webhook_events`,
  `:webhook_attempts`, and `:webhook_endpoints` (`blast_radius: :site`) with
  RecordingStudioMetrics. Events: `webhook_events.over_time` (`received_at`),
  `webhook_events.by_provider` (`provider_name`). Attempts: `webhook_attempts.by_status`.
  Endpoints: `webhook_endpoints.enabled` (current endpoints with `enabled: true`).
  Each metric is exposed on `:operations` only. `api_authorize` uses
  `RecordingStudioWebhooks::Api::Access.can_view?` (AdminRoot `:view`).
- Runtime dependency `recording_studio_metrics` `~> 0.2` (GitHub tag `v0.2.0`).

### Upgrade notes

- Bump to `0.3.0`. No migration.
- Add `recording_studio_metrics` at tag `v0.2.0`.
- This gem does not call `RecordingStudioMetrics::Api.register!`. When
  RecordingStudio API is present, the host registers Metrics endpoints once:

```ruby
RecordingStudioMetrics::Api.register!(api: :operations)
```

### Changed

- Dummy and root Gemfiles pin Recording Studio git tag `v4.2.2`
  (`036686aa4eaf4f945f920cf4b11be4e842de0aac`).
- Dummy and root Gemfiles pin RecordingStudio Accessible to `v0.11.1` and Root
  Switchable to `v0.5.3`. Admin stays on branch
  `cursor/rs41-accessible-06-upgrade-eb59` because tag `v2.0.4` does not contain
  the pinned commit.
- Dummy installs Accessible `0.8`–`0.11` migrations (dependent grants,
  invitations, string roles). Seeds and tests already grant through
  `bootstrap_owner_access!` and `grant_access`.

### Upgrade notes

- Hosts that follow the dummy stack should pin Accessible `v0.11.1` and Root
  Switchable `v0.5.3`, then run `bin/rails generate recording_studio_accessible:migrations`
  and `bin/rails db:migrate` so `recording_studio_accesses.role` is a string.
  Grant through Accessible public services; `RecordingStudio::Access` is readonly.

## [0.2.1] - 2026-09-02

Cloud Agent Builds fetch the skill pack at Build. Warm snapshots skip apt,
Ruby, database, and CSS provision. Product behavior is unchanged.

### Added

- Track `.cursor/environment.json`, `.cursor/install.sh`, `.cursor/fetch-skills.sh`,
  and `.cursor/start.sh`. Builds fetch RecordingStudio_cursor_plugin instead of
  reading a vendored pack. `.cursor/skills/` and `.cursor/rules/` stay gitignored.

### Fixed

- `.cursor/install.sh` skips apt, ruby-build, db:prepare, and tailwind when
  Ruby, bundle, and Postgres are already usable. A skippable provision
  failure no longer fails the Build. Fetch-skills always runs last.

### Upgrade notes

- No host or schema changes. Rebuild the Cloud Agent environment with Draft
  off so Build loads the pack.

## [0.2.0] - 2026-08-21

Recording Studio Webhooks now sits on the Recording Studio 4.2 kit.

### Changed

- Gemspec depends on `recording_studio`, `~> 4.2`.
- Dummy and root Gemfiles pin the current tagged kit: Recording Studio `v4.2.0`, Accessible `v0.6.1`, Root Switchable `v0.5.0`, FlatPack `v0.1.133`.
- Dummy authenticated screens use Recording Studio's shared default layout plus FlatPack CSS/JS instead of a custom sidebar shell.
- Dummy first-owner grants use `RecordingStudioAccessible.bootstrap_owner_access!`.
- Dummy tests use a no-op dispatcher (CI has Postgres only). Development still uses Sidekiq.
- Dummy copies of Admin section/screen templates were removed so Admin 2.0 renders those pages.
- FlatPack `v0.1.133` buttons take `href:`, not `url:`. Dummy sign-out/home buttons and leftover engine New/Done buttons were updated.
- Dummy ignores `app/webhooks` from Zeitwerk so Rails 8 CI eager load matches engine discovery.
- Dummy `test:dummy` loads schema without seeds (`db:create` + `db:schema:load`). `db:prepare` on a fresh CI database seeded Studio Workspace, so Admin traffic screens queried the wrong root.
- Dummy lockfile picks up Rails `8.1.3.1`, `json` `2.21.2`, `mail` `2.9.1`, and Brakeman `8.0.6` so dummy security CI can pass.
- Root RuboCop inherits `.rubocop_todo.yml` for existing engine offenses so 4.2 CI lint can pass without a style rewrite.

### Upgrade notes

1. Point host and dummy Gemfiles at Recording Studio `v4.2.0` (not `recording_studio/v3.0.0`) and Accessible `v0.6.1`.
2. Run `rails g recording_studio:migrations` (or install the harden indexes migration) and `db:migrate`.
3. Include `RecordingStudio::UsesDefaultLayout` (or set `layout "recording_studio/default_layout"`) for authenticated dummy/host screens. Do not copy a custom sidebar.
4. Keep recordable declarations. Webhooks still registers `Endpoint` as a tree object; inbound events and action attempts stay as exhaust tables, not children.
5. This gem is not a mixin. Do not add `RecordingStudio::Capabilities.*.to` here. Enable Accessible on the host root with `RecordingStudio.enable_capability(:accessible, on: Workspace)`.
6. For the first owner on an empty owned root, call `RecordingStudioAccessible.bootstrap_owner_access!(recording:, actor:)`. Use `grant_access` for later invites.
7. Admin `1.2.0` still requires Accessible `~> 0.3`. Dummy/root currently pin Admin's unpublished 4.2 line (`2.0.0` on `cursor/rs41-accessible-06-upgrade-eb59`) until that gem is tagged.
8. Ignore `app/webhooks` from Zeitwerk (`Rails.autoloaders.main.ignore`). Rails 8 eager-loads every `app/*` directory; the engine already requires those files itself.

## [0.1.0]

### Added

- Inbound-only `recording_studio_webhooks` Rails engine.
- Deterministic provider/action registries, exact and suffix-wildcard matching,
  policy snapshots, redaction, deduplication, action attemptning, retries, and
  Sidekiq/Active Job/custom dispatch.
- UUID endpoint, token, inbound-event, and action-attempt persistence.
- Recording Studio-scoped FlatPack administration, sandbox, generators, doctor
  and status tasks, dummy application, and Minitest coverage.

### Removed

- The unrelated template package, sample page table, hooks, services, and
  generic rename workflow.

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_webhooks/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/bowerbird-app/RecordingStudio_webhooks/compare/v0.6.7...v0.7.0
[0.6.7]: https://github.com/bowerbird-app/RecordingStudio_webhooks/compare/v0.6.6...v0.6.7
[0.4.0]: https://github.com/bowerbird-app/RecordingStudio_webhooks/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_webhooks/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/bowerbird-app/RecordingStudio_webhooks/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_webhooks/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio_webhooks/releases/tag/v0.1.0
