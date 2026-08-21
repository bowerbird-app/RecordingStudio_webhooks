# Getting Started

`RecordingStudioWebhooks` accepts inbound provider events, connects each endpoint to a Recording Studio recording, and runs registered local actions after validation.

For deeper details, see [Architecture](ARCHITECTURE.md), [Configuration](CONFIGURATION.md), [Operations](OPERATIONS.md), and [Security](SECURITY.md).

## Overview

The normal setup has five parts:

1. Install and mount the engine.
2. Decide who may enter the webhooks admin UI.
3. Define providers that verify and classify incoming requests.
4. Create endpoints that link providers to recordings.
5. Define queued actions for accepted event types.

```text
Provider request                  # A third party sends an HTTP request.
        |
Endpoint token                    # The engine finds the configured endpoint.
        |
Provider verification             # Your provider code accepts or rejects the request.
        |
Event and action attempt             # The engine saves redacted immutable records.
        |
Background action                 # A worker runs your local Ruby code.
```

## Install

This engine requires Recording Studio `~> 4.2`. Add the gem, generate its setup files, and apply its migration.

```bash
bundle add recording_studio_webhooks                         # Add the engine to the host application.
bin/rails generate recording_studio_webhooks:install         # Generate initializer, mount route, and migration.
bin/rails db:migrate                                         # Create endpoint, token, event, and action-attempt tables.
```

The default mount path is `/recording_studio_webhooks`. Use a shorter path when needed:

```bash
bin/rails generate recording_studio_webhooks:install \
  --mount-path=/webhooks                                    # Serve public intake and admin pages under /webhooks.
```

## Admin Access

The host supplies two callbacks because the engine cannot know how a host represents users or permissions:

- `admin_authorizer` decides whether the signed-in user can enter the webhooks admin UI.
- `admin_recording_scope` decides which recordings that user can view and manage.

When using `RecordingStudioAccessible`, delegate to its established policy instead of building a second permission system. Enable Accessible on the host root with `RecordingStudio.enable_capability(:accessible, on: Workspace)`. For the first owner on an empty owned root, call `RecordingStudioAccessible.bootstrap_owner_access!`; use `grant_access` for later invites.

```ruby
# config/initializers/recording_studio_webhooks.rb           # Load this when Rails starts.
RecordingStudioWebhooks.configure do |config|                # Open the engine configuration block.
  config.admin_authorizer = lambda do |context|              # Receive the actor and current request context.
    actor = context.actor                                     # Read the signed-in user from the host application.
    next false unless actor                                   # Deny requests without an authenticated user.

    root = context.controller.current_root_recording          # Read the selected Recording Studio root.
    next false unless root                                    # Deny requests with no recording context.

    role = context.permission.to_sym == :admin ? :admin : :view # Require admin for changes and view for reads.

    RecordingStudioAccessible.authorized?(                    # Delegate the permission decision to the host policy.
      actor: actor,                                           # Check this signed-in user.
      recording: root,                                        # Check this Recording Studio recording.
      role: role                                              # Check the access level required by this request.
    )                                                         # Return true only when policy permits it.
  rescue StandardError                                        # Treat an unexpected policy error as a denial.
    false                                                     # Fail closed rather than expose admin data.
  end                                                         # Finish authorization callback.

  config.admin_recording_scope = lambda do |context|         # Return the recordings visible in this context.
    root = context.controller.current_root_recording          # Start with the selected root recording.
    next RecordingStudio::Recording.none unless root          # Show nothing until a root is selected.

    RecordingStudio::Recording                               # Build an Active Record relation.
      .where(trashed_at: nil)                                 # Exclude recordings that are no longer active.
      .where(                                                  # Include the root and its descendants.
        "id = :root_id OR root_recording_id = :root_id",      # Match either root relationship.
        root_id: root.id                                       # Bind the selected root ID safely.
      )                                                        # Return the restricted relation to the engine.
  end                                                          # Finish scope callback.
end                                                            # Finish configuration.
```

For a global admin role, use a simpler policy:

```ruby
config.admin_authorizer = ->(context) { context.actor&.admin? } # Allow only application admins.
config.admin_recording_scope = ->(_context) {                   # Define what those admins manage.
  RecordingStudio::Recording.all                                # Allow every recording for global administrators.
}                                                                # Finish the scope callback.
```

Leaving `admin_authorizer` unset keeps the admin interface unavailable.

## Queueing and Tokens

Sidekiq is the default dispatcher. Workers receive an action-attempt UUID only, not raw payloads, request headers, or endpoint tokens.

```ruby
RecordingStudioWebhooks.configure do |config|                # Reopen the configuration block if needed.
  config.dispatcher = :sidekiq                               # Queue action attempts directly in Sidekiq.
  config.queue_name = "recording_studio_webhooks"             # Use a queue the worker will listen to.

  config.token_digest_secret = Rails.application.credentials.dig( # Read the token HMAC key from encrypted credentials.
    :recording_studio_webhooks,                               # Select the engine-specific credential section.
    :token_digest_secret                                      # Read the private key without committing it to source control.
  )                                                           # Persist only derived token digests.
end                                                            # Finish queue and token configuration.
```

```bash
bundle exec sidekiq -q recording_studio_webhooks -q default  # Process webhooks attempts and ordinary default jobs.
```

A custom dispatcher can receive the persisted attempt ID:

```ruby
config.dispatcher = lambda do |action_attempt_id|               # Receive the UUID of an already-persisted attempt.
  ExternalQueue.publish(action_attempt_id)                       # Publish only that ID to the host queue system.
end                                                            # The queue worker must execute the same attempt later.
```

## Provider Definitions

A provider verifies the sender, extracts an event type, and optionally extracts a stable provider event ID. Keep provider code in the host app, such as `app/webhooks/providers/stripe.rb`.

```ruby
# app/webhooks/providers/stripe.rb                            # Keep provider-specific code in the host application.
module Webhooks                                               # Use an application namespace.
  module Providers                                            # Group provider definitions.
    class Stripe < RecordingStudioWebhooks::Provider          # Use the optional class-based provider helper.
      def self.register!                                      # Register explicitly during boot.
        register(                                             # Add a provider definition to the engine registry.
          "stripe",                                          # Use a stable lowercase key for endpoints and actions.
          signature_verifier: lambda { |context|              # Verify original request bytes in memory.
            secret = ENV.fetch("STRIPE_WEBHOOK_SECRET", "")  # Read the signing secret from the runtime environment.
            signature = context.headers["stripe-signature"].to_s # Read Stripe's signature header.
            next false if secret.empty? || signature.empty?   # Reject missing setup and unsigned requests.

            Stripe::Webhook.construct_event(                  # Use Stripe's official library to validate the request.
              context.raw_payload,                            # Provide untouched bytes required for signature verification.
              signature,                                      # Provide the signature from the request.
              secret                                          # Provide the host's private signing secret.
            )                                                 # Raise when the event is not authentic.
            true                                              # Accept the request after verification succeeds.
          rescue StandardError                                # Handle provider-library verification failures.
            false                                             # Reject invalid requests without leaking details.
          },                                                  # Finish signature verification.
          event_type_extractor: ->(payload) { payload["type"] }, # Extract the type used to select actions.
          event_id_extractor: ->(payload) { payload["id"] } # Extract a stable ID used for deduplication.
        )                                                     # Finish registration.
      end                                                     # Finish register!.
    end                                                       # Finish the provider class.
  end                                                         # Finish provider namespace.
end                                                           # Finish host namespace.

Webhooks::Providers::Stripe.register!                        # Register the provider during boot.
```

Use explicit roots to load trusted registration files. The engine requires files in lexical order and does not infer constants from filenames. Rails 8 autoloads every `app/*` directory, so tell Zeitwerk to ignore the discovery folders or CI eager load will look for `Providers::Demo` instead of `Webhooks::Providers::Demo`:

```ruby
# config/application.rb
initializer :ignore_webhook_discovery_from_zeitwerk, before: :setup_main_autoloader do
  Rails.autoloaders.main.ignore(root.join("app/webhooks"))
end
```

```ruby
RecordingStudioWebhooks.configure do |config|                # Configure local registration file discovery.
  config.provider_roots = [Rails.root.join("app/webhooks/providers").to_s] # Trust this provider directory.
  config.action_roots = [Rails.root.join("app/webhooks/actions").to_s]     # Trust this action directory.
  config.automatic_discovery = true                           # Require files from those directories at boot.
end                                                            # Finish discovery configuration.
```

## Endpoints and Tokens

Create endpoints in the webhooks admin UI. An endpoint connects one Recording Studio recording to one registered provider. It has a label, optional safe metadata, and one or more rotating tokens.

After issuing a token, copy it immediately. The database keeps only its digest.

```text
POST /webhooks/inbound/:endpoint_token                        # Replace /webhooks with the engine mount path.
Authorization: Bearer rswh_example_token                      # Send the token issued for this endpoint.
Content-Type: application/json                                # Send a supported JSON content type.
```

When a provider cannot use `Authorization`, send the supported alternate header. Do not put tokens in a query string.

```text
X-Recording-Studio-Webhook-Token: rswh_example_token         # Send the same issued token in the alternate header.
```

Use metadata for non-secret operational context only:

```ruby
endpoint = RecordingStudioWebhooks::Endpoint.new(            # Build through a trusted service or console flow.
  recording_studio_recording_id: recording.id,                # Attach the endpoint to one stable recording.
  provider_name: "stripe",                                   # Select the registered provider.
  label: "Billing production",                               # Give administrators a clear display name.
  enabled: true,                                              # Accept valid inbound requests for this endpoint.
  metadata: { environment: "production", owner: "payments" } # Store only safe, human-useful context.
)                                                             # Persist using the host's approved endpoint workflow.
```

Never store signing secrets, tokens, or secret-store locations in endpoint metadata or identity fields.

## Action Definitions

Actions are local application code that run after a matching event is accepted and planned. They receive redacted event data, not the original token or unfiltered payload.

```ruby
# app/webhooks/actions/stripe/payment_intent_succeeded_action.rb # Keep business behavior in the host app.
module Webhooks                                               # Use the host namespace.
  module Actions                                              # Group all action definitions.
    module Stripe                                             # Group Stripe-specific actions.
      class PaymentIntentSucceededAction < RecordingStudioWebhooks::Action # Use the optional action helper.
        def self.call(context)                                # The engine calls this when the attempt executes.
          event = context.inbound_event                       # Read the saved, redacted event.
          PaymentIntents.sync_from_webhook(event)             # Perform the application's local work.
          true                                                # Finish successfully.
        end                                                   # Finish execution method.

        def self.register!                                    # Define explicit boot-time registration.
          register(                                           # Add the action to the engine registry.
            "stripe.payment_intent_succeeded",               # Use a unique action name for logs and attempts.
            provider: "stripe",                              # Match only events from this provider.
            event: "payment_intent.succeeded",               # Match this exact provider event type.
            policy: { max_retries: 2 }                        # Retry twice after an initial failure.
          )                                                   # Finish action registration.
        end                                                   # Finish register!.
      end                                                     # Finish action class.
    end                                                       # Finish Stripe namespace.
  end                                                         # Finish action namespace.
end                                                           # Finish host namespace.

Webhooks::Actions::Stripe::PaymentIntentSucceededAction.register! # Register the action during boot.
```

Use one final wildcard when a handler covers related names:

```ruby
register(                                                     # Register a shared action handler.
  "stripe.payment_intent_events",                            # Use a separate unique action name.
  provider: "stripe",                                        # Restrict matching to Stripe events.
  event: "payment_intent.*"                                  # Match event types beginning with payment_intent.
)                                                             # Only a final .* wildcard is supported.
```

Exact event names take precedence over wildcard patterns.

## Execution Policy

Policies control planning, execution order, retries, redaction, and deduplication. The most specific value wins:

```text
Endpoint override                                             # Highest priority: one endpoint has special behavior.
Action policy                                                 # Next: one action needs different behavior.
Provider policy                                               # Next: all events from a provider share a rule.
Global default policy                                         # Lowest priority: fallback for the engine.
```

```ruby
RecordingStudioWebhooks.configure do |config|                # Set the default when nothing more specific applies.
  config.default_policy = {                                  # Define baseline execution behavior.
    enabled: true,                                           # Attempt and execute matching actions.
    execution_mode: :independent,                            # Allow matching actions to run separately.
    max_retries: 3,                                          # Retry up to three times after the first failure.
    retry_backoff: 30,                                       # Start retries after 30 seconds.
    max_retry_backoff: 600,                                  # Cap exponential retry delay at ten minutes.
    deduplicate: true                                        # Avoid creating duplicate attempts for the same event.
  }                                                          # Finish policy values.
end                                                            # Finish policy configuration.
```

## Test Public Intake

Use a test endpoint token and test provider secret locally. Production requests must carry a provider-valid signature.

```bash
curl --request POST \
  "http://localhost:3000/webhooks/inbound/rswh_example_token" \
  --header "Authorization: Bearer rswh_example_token" \
  --header "Content-Type: application/json" \
  --data '{"id":"evt_example","type":"payment_intent.succeeded"}'
# Send a POST to an endpoint URL issued in the admin UI.
# Send the endpoint token as a credential header.
# Declare JSON so the engine can validate the content type.
# Use a representative payload; production requests need a valid provider signature.
```

Responses are intentionally generic: `accepted`, `duplicate`, `unauthorized`, `not_found`, `invalid`, or `unavailable`. Use the webhooks admin event and action-attempt screens to follow accepted work.

## Operations

These tasks provide safe diagnostics and recovery. They do not print plaintext tokens, raw payloads, headers, or HMAC keys.

```bash
bin/rails recording_studio_webhooks:status                   # Display safe registry and persistence status.
bin/rails recording_studio_webhooks:doctor                   # Check deployment and configuration readiness.
bin/rails recording_studio_webhooks:dispatch_due             # Recover pending attempts after outages or restarts.
```

Schedule `dispatch_due` with the host scheduler. The engine does not delete records automatically, so define retention that meets the host's audit and privacy requirements.

## Production Checklist

```text
[ ] The engine migration has run.                             # All four engine tables exist in production.
[ ] admin_authorizer fails closed.                            # Unauthorized users cannot use administration.
[ ] admin_recording_scope stays narrow.                       # Users see only recordings they may manage.
[ ] Provider signatures are verified.                         # Knowing a URL alone cannot authenticate a request.
[ ] Provider secrets stay outside source control.             # Use credentials or environment variables.
[ ] A worker listens to the configured queue.                 # Accepted attempts can execute.
[ ] dispatch_due is scheduled.                                # Recoverable attempts are retried after outages.
[ ] Retention and monitoring are defined.                     # Stored history meets operational and privacy requirements.
```