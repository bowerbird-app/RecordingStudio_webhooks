# Changelog

## Unreleased

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
