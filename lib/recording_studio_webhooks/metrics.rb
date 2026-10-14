# frozen_string_literal: true

require_relative "api/access"
require "recording_studio_metrics"

module RecordingStudioWebhooks
  module Metrics
    EVENTS = :webhook_events
    ATTEMPTS = :webhook_attempts
    ENDPOINTS = :webhook_endpoints
    API = :operations
    EXPOSE = { api: [API] }.freeze
    AUTHORIZE = ->(context) { RecordingStudioWebhooks::Api::Access.can_view?(context) }
    ENABLED = ->(relation) { relation.where(enabled: true) }
    CURRENT_ENDPOINTS = ->(relation) { relation.merge(RecordingStudioWebhooks::Endpoint.current) }
    # A retry is stuck once ActionAttempt.due would have picked it up at least
    # the longest default retry backoff ago (Policy max_retry_backoff, 300s).
    STUCK_RETRY_GRACE = RecordingStudioWebhooks::Policy::DEFAULT_VALUES.fetch("max_retry_backoff").seconds
    STUCK_GROUP_BY = %i[action_name].freeze
    STUCK = lambda { |relation|
      relation.merge(RecordingStudioWebhooks::ActionAttempt.due(Time.current - STUCK_RETRY_GRACE))
              .where.not(next_attempt_at: nil)
    }
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
    OLDEST_STUCK_AGE = lambda { |relation, _context|
      oldest = relation.minimum(:next_attempt_at)
      oldest ? (Time.current - oldest).floor : nil
    }

    module_function

    def register!
      return if RecordingStudioMetrics.find("webhook_events.over_time")

      register_events!
      register_attempts!
      register_endpoints!
    end

    def register_events!
      RecordingStudioMetrics.register(
        EVENTS,
        model: RecordingStudioWebhooks::InboundEvent,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) { RecordingStudioWebhooks::Metrics.define_events(self) }
    end

    def register_attempts!
      RecordingStudioMetrics.register(
        ATTEMPTS,
        model: RecordingStudioWebhooks::ActionAttempt,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) { RecordingStudioWebhooks::Metrics.define_attempts(self) }
    end

    def register_endpoints!
      RecordingStudioMetrics.register(
        ENDPOINTS,
        model: RecordingStudioWebhooks::Endpoint,
        blast_radius: :site,
        api_authorize: AUTHORIZE,
        scope: CURRENT_ENDPOINTS
      ) { RecordingStudioWebhooks::Metrics.define_endpoints(self) }
    end

    def define_events(dsl)
      dsl.timeseries :over_time, title: "Webhook events over time", field: :received_at, expose: EXPOSE
      dsl.breakdown :by_provider, title: "Webhook events by provider", field: :provider_name, expose: EXPOSE
    end

    def define_attempts(dsl)
      dsl.breakdown :by_status, title: "Webhook attempts by status", field: :status, expose: EXPOSE
      dsl.count :stuck, title: "Stuck webhook retries", description: stuck_description,
                        expose: EXPOSE, scope: STUCK, group_by: STUCK_GROUP_BY,
                        filters: attempt_filters
      dsl.custom :oldest_stuck_age, title: "Oldest stuck webhook retry age", description: oldest_stuck_description,
                                    result_type: :scalar, unit: "seconds", expose: EXPOSE, scope: STUCK,
                                    filters: attempt_filters, &OLDEST_STUCK_AGE
    end

    def stuck_description
      "Attempts in pending or retrying whose next_attempt_at is at least #{STUCK_RETRY_GRACE.to_i} seconds ago."
    end

    def oldest_stuck_description
      "Seconds since the earliest next_attempt_at among stuck webhook retries; null when none are stuck."
    end

    def define_endpoints(dsl)
      dsl.count :enabled, title: "Enabled webhook endpoints", expose: EXPOSE, scope: ENABLED
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
