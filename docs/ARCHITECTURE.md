# Architecture

The engine has one direction of travel: provider request → authenticated intake
→ immutable event and attempt records → local action execution. It has no outgoing
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
| action attempts | action snapshot, state, retries, and append-only attempts |

Endpoints are tree objects: people create and manage them, so they are
recordings. Inbound events and action attempts are exhaust (logs), not children
of the recording tree.

The event stores the endpoint, token, and intake-policy snapshot. Each action
attempt stores endpoint, token, policy, and action snapshots. This means later
configuration changes do not rewrite historical provenance.

## Registration and selection

Registries are mutex-protected and expose lexical ordering. Actions are
selected using exact event matching first, then suffix wildcard specificity,
priority, and name. Planning resolves policy in the documented precedence and
persists a attempt before dispatch.

## Execution boundary

Job payloads contain only an action-attempt UUID. Workers look up the attempt, claim
it under a database lock, invoke the currently registered handler, and record a
sanitized lifecycle transition. Sequential attempts dispatch the next ready attempt;
independent attempts are independently dispatchable.
