# Security Model

## Credentials

Endpoint token plaintext exists only during issuance. The database stores a
SHA-256 digest or an HMAC-SHA-256 digest when `token_digest_secret` is set,
plus a short non-secret prefix. Rotation revokes older active tokens under a
lock. Authentication considers only a current, unrevoked, unexpired token and
uses a constant-time digest comparison.

Never put provider signing material, endpoint tokens, or secret-store paths in
endpoint identity, metadata, policy, action snapshots, job arguments, source
control, or logs.

## Intake

Public intake uses `ActionController::API`, so it is stateless and has no
cookie-backed CSRF surface. It accepts JSON with a credential header, validates
request size and content type, and emits generic responses. Administrative
mutations retain standard Rails CSRF protection and require an explicit host
authorizer.

The public intake guard prevents Rails parameter parsing and request logging
from buffering or recording the raw JSON body. It applies a declared-length
check and the controller applies a bounded read for chunked requests. Raw
payloads are used in memory for JSON parsing and optional signature
verification. Before persistence, the engine filters configured and
secret-looking keys recursively. It stores a one-way canonical payload digest
for deduplication and only an allowlisted provenance subset.

## Execution

Actions receive redacted data only. Worker errors are collapsed into generic
state codes. The direct Sidekiq payload and Active Job payload contain an
action-attempt ID only.

## Sandbox

The admin sandbox does not create an event, attempt, attempt, job, or log entry.
It displays only a redacted result and never executes the matching handlers.
Its request field is included in the engine parameter filter as a defense in
depth measure for normal Rails request logging.
