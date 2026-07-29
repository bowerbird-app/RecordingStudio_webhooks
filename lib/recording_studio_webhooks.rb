# frozen_string_literal: true

# lib/recording_studio_webhooks.rb
require "json"
require "date"
require "openssl"
require "securerandom"
require "set"

require "recording_studio_webhooks/version"
require "recording_studio_webhooks/errors"
require "recording_studio_webhooks/immutable_snapshot"
require "recording_studio_webhooks/result"
require "recording_studio_webhooks/event_pattern"
require "recording_studio_webhooks/policy"
require "recording_studio_webhooks/policy_resolver"
require "recording_studio_webhooks/provider_definition"
require "recording_studio_webhooks/action_definition"
require "recording_studio_webhooks/registry"
require "recording_studio_webhooks/provider"
require "recording_studio_webhooks/action"
require "recording_studio_webhooks/configuration"
require "recording_studio_webhooks/canonical_json"
require "recording_studio_webhooks/redactor"
require "recording_studio_webhooks/token_digest"
require "recording_studio_webhooks/recording_studio_gateway"
require "recording_studio_webhooks/dispatcher"
require "recording_studio_webhooks/admin_webhooks_section"
require "recording_studio_webhooks/admin/registration"
require "recording_studio_webhooks/public_intake_guard"
require "recording_studio_webhooks/engine"

module RecordingStudioWebhooks
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      configuration
    end

    def providers = configuration.providers

    def actions = configuration.actions

    def register_provider(name, implementation = nil, **options, &)
      providers.register(name, implementation, **options, &)
    end

    def register_action(name, implementation = nil, **options, &)
      actions.register(name, implementation, **options, &)
    end

    # A serializable, intentionally non-secret description of the current setup.
    def report = configuration.report

    # Endpoint snapshots now follow Recording Studio's standard record/revise
    # lifecycle and are declared recordables in the endpoint model.
    def configure_recordables!
      RecordingStudioGateway.available?
    end
  end
end
