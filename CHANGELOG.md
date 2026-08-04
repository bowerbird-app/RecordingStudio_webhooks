# Changelog

## Unreleased

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
