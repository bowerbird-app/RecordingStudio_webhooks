# frozen_string_literal: true

module RecordingStudioWebhooks
  # Coordinates endpoint persistence with the matching Recording Studio audit
  # event so an audit failure cannot leave an untracked endpoint mutation.
  class EndpointLifecycle
    IMMUTABLE_REVISION_ATTRIBUTES = %i[provider_name recording_studio_recording_id identity].freeze

    def self.create!(...) = new(...).create!
    def self.update!(...) = new(...).update!

    def initialize(endpoint:, actor:, attributes: nil)
      @endpoint = endpoint
      @actor = actor
      @attributes = attributes
    end

    def create!
      Endpoint.transaction do
        parent_recording = endpoint.recording_studio_recording
        root_recording = parent_recording.root_recording_or_self
        attributes_for_record = endpoint.attributes.except("id", "created_at", "updated_at", "recording_studio_recording_id")

        stable_recording = RecordingStudioGateway.record!(
          root_recording: root_recording,
          recordable_class: Endpoint,
          parent_recording: parent_recording,
          actor: actor,
          metadata: { provider_name: endpoint.provider_name }
        ) do |recordable|
          recordable.assign_attributes(attributes_for_record)
          # Satisfy endpoint DB constraints before Recording Studio creates its stable recording row.
          recordable.recording_studio_recording_id = parent_recording.id
        end

        created_endpoint = stable_recording.recordable
        # Recordables are immutable once persisted, so use a relation update
        # to align the endpoint's routing recording id with its stable recording.
        Endpoint.where(id: created_endpoint.id).update_all(
          recording_studio_recording_id: stable_recording.id,
          updated_at: Time.current
        )
        created_endpoint.reload
        created_endpoint.audit!(
          action: "recording_studio_webhooks.endpoint.created",
          actor: actor,
          metadata: { endpoint_id: created_endpoint.id }
        )
        created_endpoint
      end
    end

    def update!
      Endpoint.transaction do
        enforce_revision_immutability!

        stable_recording = endpoint.recording_studio_recording
        root_recording = stable_recording.root_recording_or_self
        now = Time.current

        revised_recording = RecordingStudioGateway.revise!(
          root_recording: root_recording,
          stable_recording: stable_recording,
          actor: actor,
          metadata: { endpoint_id: endpoint.id }
        ) do |recordable|
          recordable.assign_attributes(attributes || {})
        end

        replacement = Endpoint.find(revised_recording.recordable_id)
        endpoint.endpoint_tokens.update_all(endpoint_id: replacement.id, updated_at: now)

        replacement.audit!(
          action: "recording_studio_webhooks.endpoint.revised",
          actor: actor,
          metadata: {
            endpoint_id: replacement.id,
            previous_endpoint_id: endpoint.id
          }
        )
        replacement
      end
    end

    private

    attr_reader :endpoint, :actor, :attributes

    def audit!(action)
      endpoint.audit!(
        action: action,
        actor: actor,
        metadata: { endpoint_id: endpoint.id }
      )
    end

    def enforce_revision_immutability!
      return if attributes.blank?

      immutable_changed = IMMUTABLE_REVISION_ATTRIBUTES.any? do |name|
        next false unless attributes.key?(name) || attributes.key?(name.to_s)

        incoming = attributes.key?(name) ? attributes[name] : attributes[name.to_s]
        incoming != endpoint.public_send(name)
      end
      return unless immutable_changed

      raise ActiveRecord::ReadOnlyRecord, "endpoint identity and recording linkage are immutable"
    end
  end
end
