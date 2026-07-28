# Architecture

The engine has one direction of travel: provider request → authenticated intake
→ immutable event and plan records → local action execution. It has no outgoing
HTTP delivery client.

## Stable ownership

Each endpoint belongs to a `RecordingStudio::Recording`. The recording ID,
provider name, endpoint key, and identity JSON become read-only after creation.
This prevents webhook ownership from silently moving when a host recordable is
edited or reassigned.

## Persistence boundary

There are four engine tables, all with UUID primary keys:

| Table | Responsibility |
| --- | --- |
| endpoints | stable Recording Studio ownership and endpoint policy |
| endpoint tokens | digest/prefix/lifecycle only |
| inbound events | redacted receipt and immutable intake snapshots |
| action plans | action snapshot, state, retries, and append-only attempts |

The event stores the endpoint, token, and intake-policy snapshot. Each action
plan stores endpoint, token, policy, and action snapshots. This means later
configuration changes do not rewrite historical provenance.

## Registration and selection

Registries are mutex-protected and expose lexical ordering. Actions are
selected using exact event matching first, then suffix wildcard specificity,
priority, and name. Planning resolves policy in the documented precedence and
persists a plan before dispatch.

## Execution boundary

Job payloads contain only an action-plan UUID. Workers look up the plan, claim
it under a database lock, invoke the currently registered handler, and record a
sanitized lifecycle transition. Sequential plans dispatch the next ready plan;
independent plans are independently dispatchable.
