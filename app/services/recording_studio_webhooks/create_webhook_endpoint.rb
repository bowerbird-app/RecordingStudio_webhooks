# frozen_string_literal: true

# app/services/recording_studio_webhooks/create_webhook_endpoint.rb
module RecordingStudioWebhooks
  # Creates one stable endpoint Recording and its one stable token child
  # Recording. The mutable-looking values are immutable recordable snapshots.
  class CreateWebhookEndpoint
    class Issuance
      attr_reader :endpoint_recording, :endpoint_token_recording, :endpoint_snapshot, :endpoint_token_snapshot

      def initialize(endpoint_recording:, endpoint_token_recording:, endpoint_snapshot:, endpoint_token_snapshot:, plaintext_token:)
        @endpoint_recording = endpoint_recording
        @endpoint_token_recording = endpoint_token_recording
        @endpoint_snapshot = endpoint_snapshot
        @endpoint_token_snapshot = endpoint_token_snapshot
        @plaintext_token = plaintext_token
      end

      def plaintext_token
        raise Error, "plaintext token has already been disclosed" unless @plaintext_token

        token = @plaintext_token
        @plaintext_token = nil
        token
      end
      alias token plaintext_token

      def inspect
        "#<#{self.class.name} endpoint_recording_id=#{endpoint_recording.id.inspect} token=[FILTERED]>"
      end
    end

    def self.call(...) = new(...).call

    def initialize(root_recording:, provider_name:, enabled: true, policy_overrides: {}, event_policies: {},
      metadata: {}, token_expires_at: nil, token_metadata: {}, actor: nil)
      @root_recording = root_recording
      @provider_name = provider_name
      @enabled = enabled
      @policy_overrides = policy_overrides
      @event_policies = event_policies
      @metadata = metadata
      @token_expires_at = token_expires_at
      @token_metadata = token_metadata
      @actor = actor
    end

    def call
      return unavailable unless RecordingStudioGateway.available?
      return Result.new(status: 422, code: "provider_unavailable") unless registered_provider?(@provider_name)

      endpoint_recording = nil
      token_recording = nil
      plaintext_token = generate_token
      now = Time.current

      ApplicationRecord.transaction do
        root = RecordingStudioGateway.root_recording!(@root_recording)
        endpoint_recording = RecordingStudioGateway.record!(
          root_recording: root,
          recordable_class: WebhookEndpoint,
          parent_recording: root,
          actor: @actor,
          metadata: { source: "recording_studio_webhooks", operation: "endpoint_created" }
        ) do |snapshot|
          snapshot.assign_attributes(endpoint_attributes)
        end

        token_recording = RecordingStudioGateway.record!(
          root_recording: root,
          recordable_class: WebhookEndpointToken,
          parent_recording: endpoint_recording,
          actor: @actor,
          metadata: { source: "recording_studio_webhooks", operation: "token_issued" }
        ) do |snapshot|
          snapshot.assign_attributes(token_attributes(plaintext_token, now))
        end

        RecordingStudioGateway.log_event!(
          root_recording: root,
          recording: endpoint_recording,
          actor: @actor,
          action: "recording_studio_webhooks.endpoint.created",
          metadata: {
            endpoint_recording_id: endpoint_recording.id,
            endpoint_token_recording_id: token_recording.id
          }
        )
      end

      Result.new(
        status: 201,
        code: "endpoint_created",
        record: Issuance.new(
          endpoint_recording: endpoint_recording,
          endpoint_token_recording: token_recording,
          endpoint_snapshot: endpoint_recording.recordable,
          endpoint_token_snapshot: token_recording.recordable,
          plaintext_token: plaintext_token
        )
      )
    rescue RecordingStudioUnavailableError, RecordingStudioConfigurationError
      unavailable
    rescue ActiveRecord::RecordInvalid, ArgumentError
      Result.new(status: 422, code: "endpoint_invalid")
    rescue StandardError
      Result.new(status: 503, code: "endpoint_unavailable")
    end

    private

    def unavailable = Result.new(status: 503, code: "recording_studio_unavailable")

    def endpoint_attributes
      {
        provider_name: @provider_name.to_s.downcase,
        enabled: @enabled,
        policy_overrides: Policy.normalize_override(@policy_overrides || {}),
        event_policies: PolicyResolver.normalize_event_policies(@event_policies || {}),
        metadata: @metadata || {}
      }
    end

    def token_attributes(plaintext_token, now)
      {
        digest: TokenDigest.digest(plaintext_token),
        prefix: plaintext_token.first(13),
        enabled: true,
        active_at: now,
        expires_at: @token_expires_at,
        metadata: @token_metadata || {}
      }
    end

    def generate_token = "rswh_#{SecureRandom.urlsafe_base64(32)}"

    def registered_provider?(name)
      RecordingStudioWebhooks.configuration.providers.fetch(name).present?
    end
  end
end
