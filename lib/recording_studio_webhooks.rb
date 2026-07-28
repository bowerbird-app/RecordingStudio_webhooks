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

    # Registers the immutable webhook recordables with Recording Studio when it
    # is available. Hosts may set `recording_studio_parent_types` explicitly;
    # otherwise the currently configured Recording Studio root types are used.
    def configure_recordables!
      return false unless RecordingStudioGateway.available?

      parent_types = configuration.recording_studio_parent_types
      parent_types = ::RecordingStudio.root_recordable_types if parent_types.empty?
      return false if parent_types.empty?

      endpoint_class = RecordingStudioWebhooks::Endpoint
      token_class = RecordingStudioWebhooks::EndpointToken

      endpoint_class.recording_studio_recordable(
        label: "Webhook endpoint",
        root: false,
        allowed_parent_types: parent_types
      )
      token_class.recording_studio_recordable(
        label: "Webhook endpoint token",
        root: false,
        allowed_parent_types: [endpoint_class.name]
      )

      ::RecordingStudio.register_recordable_type(endpoint_class)
      ::RecordingStudio.register_recordable_type(token_class)
      true
    end
  end
end
