# Operations

## Queueing

Sidekiq is the default direct dispatcher. The worker receives a UUID only, so
queue backends do not receive raw payloads, headers, endpoint tokens, or secret
material. For Active Job set `dispatcher = :active_job`; for another backend,
configure a callable that accepts a plan ID and optional schedule.

## Retry behavior

`max_retries` counts retry opportunities after the initial execution. Delay is
`retry_backoff * 2^(attempt - 1)` and is capped by `max_retry_backoff`. Errors
are recorded as generic codes, not exception messages.

## Diagnostics

Run:

```bash
bin/rails recording_studio_webhooks:status
bin/rails recording_studio_webhooks:doctor
bin/rails recording_studio_webhooks:dispatch_due
```

Use `status` for safe registry/table visibility. `doctor` is suitable for
deployment readiness checks. It intentionally does not print HMAC values,
tokens, raw payloads, request headers, or provider secret locations.

Schedule `dispatch_due` through the host scheduler. It reconciles plans left
pending after a process crash, retries temporary dispatcher outages, and
requeues stale queue claims without exposing event data.

## Retention

The engine does not delete endpoint, event, or plan records automatically.
Hosts should define retention according to their audit and privacy obligations,
using normal database operations that preserve foreign-key integrity.
