# frozen_string_literal: true

module RecordingStudioWebhooks
  # Coordinates endpoint persistence with the matching Recording Studio audit
  # event so an audit failure cannot leave an untracked endpoint mutation.
  class EndpointLifecycle
    def self.create!(...) = new(...).create!
    def self.update!(...) = new(...).update!

    def initialize(endpoint:, actor:, attributes: nil)
      @endpoint = endpoint
      @actor = actor
      @attributes = attributes
    end

    def create!
      Endpoint.transaction do
        endpoint.save!
        audit!("recording_studio_webhooks.endpoint.created")
      end
      endpoint
    end

    def update!
      Endpoint.transaction do
        endpoint.update!(attributes)
        audit!("recording_studio_webhooks.endpoint.revised")
      end
      endpoint
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
  end
end
