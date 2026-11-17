# Security Model

## Credentials

Endpoint token plaintext exists only during issuance. The database stores a
SHA-256 digest or an HMAC-SHA-256 digest when `token_digest_secret` is set,
plus a short non-secret prefix. Rotation revokes older active tokens under a
lock. Authentication considers only a current, unrevoked, unexpired token and
uses a constant-time digest comparison. The token recording, the endpoint
recording, and that endpoint's root recording must all be kept. A trashed
endpoint or workspace is rejected with the same generic unauthorized
response as an unknown or disabled endpoint.

Never put provider signing material, endpoint tokens, or secret-store paths in
endpoint identity, metadata, policy, action snapshots, job arguments, source
control, or logs. The built-in HMAC verifier is the exception for storage: its
per-endpoint secret lives in the encrypted `signing_secret` column, is shown
once at creation, and is omitted from `inspect`.

Dummy app credentials live in `test/dummy/config/credentials.yml.enc`. That file
is encrypted with the shared RecordingStudio_* development master key (dev/test
only; this gem has no production site). Keep the encrypted file. Do not mint a
per-repo dummy master key. Set `RAILS_MASTER_KEY`, or write the shared key to
`test/dummy/config/master.key`. That file is gitignored and is never committed.

## Staff admin

Staff admin reads use the current root. Accessible grants on that root
decide who can open the screens. The attempt page loads an attempt only
when its endpoint recording is in that root. The stuck retries card uses
that same set of attempts. Provider, endpoint, and action menus list the
current endpoints on that root.

The operations metrics API stays site-wide. It still requires view access
on the admin root.

## Intake

Public intake uses `ActionController::API`, so it is stateless and has no
cookie-backed CSRF surface. It accepts JSON with a credential header, validates
request size and content type, and emits generic responses. A path token is
accepted only when the provider has a signature check. Unsigned providers must
use `Authorization: Bearer` or `X-Recording-Studio-Webhook-Token`.
`ActionDispatch::Request#filtered_path` redacts an `rswh_` segment so the
request log line does not include the token, and `endpoint_token` stays in
`filter_parameters`. Administrative mutations retain standard Rails CSRF protection and
authorize through Accessible on the current root unless the host replaces
`admin_authorizer`.

The public intake guard prevents Rails parameter parsing and request logging
from buffering or recording the raw JSON body. It applies a declared-length
check and the controller applies a bounded read for chunked requests. Raw
payloads are used in memory for JSON parsing and signature verification. Before persistence, the engine filters configured and
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
