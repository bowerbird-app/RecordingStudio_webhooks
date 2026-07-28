# frozen_string_literal: true

# app/services/recording_studio_webhooks/revise_webhook_endpoint.rb
module RecordingStudioWebhooks
  # Revises the endpoint snapshot without changing its Recording Studio
  # identity or its token child identity.
  class ReviseWebhookEndpoint
    def self.call(...) = new(...).call

    def initialize(endpoint_recording:, attributes:, root_recording: nil, actor: nil)
      @endpoint_recording = endpoint_recording
      @attributes = attributes.respond_to?(:to_h) ? attributes.to_h : {}
      @root_recording = root_recording
      @actor = actor
    end

    def call
      return unavailable unless RecordingStudioGateway.available?
      return Result.new(status: 422, code: "provider_unavailable") if provider_changed_to_unregistered?

      root = @root_recording || @endpoint_recording&.root_recording_or_self
      revised = RecordingStudioGateway.revise!(
        root_recording: root,
        stable_recording: @endpoint_recording,
        actor: @actor,
        metadata: { source: "recording_studio_webhooks", operation: "endpoint_revised" }
      ) { |snapshot| snapshot.assign_attributes(permitted_attributes) }

      RecordingStudioGateway.log_event!(
        root_recording: root,
        recording: revised,
        actor: @actor,
        action: "recording_studio_webhooks.endpoint.revised",
        metadata: { endpoint_recording_id: revised.id }
      )
      Result.new(status: 200, code: "endpoint_revised", record: revised)
    rescue RecordingStudioUnavailableError, RecordingStudioConfigurationError
      unavailable
    rescue ActiveRecord::RecordInvalid, ArgumentError
      Result.new(status: 422, code: "endpoint_invalid")
    rescue StandardError
      Result.new(status: 503, code: "endpoint_unavailable")
    end

    private

    def unavailable = Result.new(status: 503, code: "recording_studio_unavailable")

    def permitted_attributes
      @attributes.stringify_keys.slice("provider_name", "enabled", "policy_overrides", "event_policies", "metadata")
        .transform_keys(&:to_sym)
    end

    def provider_changed_to_unregistered?
      provider_name = permitted_attributes[:provider_name]
      provider_name.present? && RecordingStudioWebhooks.configuration.providers.fetch(provider_name).nil?
    end
  end
end
