# frozen_string_literal: true

module RecordingStudioWebhooks
  # Metric filters named and matched like the Admin Events and Action attempts screens.
  module MetricFilters
    FILTER_BY_PROVIDER = lambda { |relation, value, _context|
      relation.joins(:inbound_event).where(recording_studio_webhooks_inbound_events: { provider_name: value })
    }
    FILTER_BY_ENDPOINT = lambda { |relation, value, _context|
      relation.joins(inbound_event: :endpoint).where(recording_studio_webhooks_endpoints: { label: value })
    }
    FILTER_BY_ACTION_NAME = lambda { |relation, value, _context|
      all = RecordingStudioWebhooks::AdminWebhooksTrafficDefinition::ACTION_FILTER_ALL
      value == all ? relation : relation.where(action_name: value)
    }

    module_function

    # Same names and matching rules as the Admin "Events" screen filters.
    def event_filters
      [
        RecordingStudioMetrics::Filter.new(:provider_name, type: :string, field: :provider_name),
        RecordingStudioMetrics::Filter.new(:endpoint_id, type: :string, field: :endpoint_id),
        RecordingStudioMetrics::Filter.new(:event_type, type: :string, field: :event_type)
      ]
    end

    # Same names and matching rules as the Admin "Action attempts" screen filters.
    def attempt_filters
      [
        RecordingStudioMetrics::Filter.new(:provider, type: :string, handler: FILTER_BY_PROVIDER),
        RecordingStudioMetrics::Filter.new(:endpoint, type: :string, handler: FILTER_BY_ENDPOINT),
        RecordingStudioMetrics::Filter.new(:action_name, type: :string, handler: FILTER_BY_ACTION_NAME),
        RecordingStudioMetrics::Filter.new(:event_id, type: :string, field: :inbound_event_id)
      ]
    end
  end
end
