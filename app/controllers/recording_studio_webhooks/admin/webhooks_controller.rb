# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class WebhooksController < BaseController
      def show
        @providers = webhook_configuration.providers.all.sort_by(&:name)
        @actions = webhook_configuration.actions.all.sort_by(&:sort_key)

        scoped_endpoints = endpoint_scope
        @endpoint_count = scoped_endpoints.count
        @enabled_endpoint_count = scoped_endpoints.where(enabled: true).count
        @disabled_endpoint_count = @endpoint_count - @enabled_endpoint_count

        scoped_events = InboundEvent.where(endpoint_id: scoped_endpoints.select(:id))
        @event_count = scoped_events.count
        @recent_events = scoped_events.order(received_at: :desc).limit(25)

        scoped_plans = ActionPlan.joins(:inbound_event).where(
          inbound_event: { endpoint_id: scoped_endpoints.select(:id) }
        )
        @failed_plan_count = scoped_plans.where(status: "failed").count
        @retrying_plan_count = scoped_plans.where(status: "retrying").count
        @blocked_plan_count = scoped_plans.where(status: "pending").count
        @paused_plan_count = scoped_endpoints.where(enabled: false).count

        @dispatcher_name = webhook_configuration.dispatcher.is_a?(Symbol) ? webhook_configuration.dispatcher.to_s : "custom"
        @dispatcher_healthy = dispatcher_healthy?
      end

      private

      def dispatcher_healthy?
        return true unless webhook_configuration.dispatcher == :sidekiq
        return false unless defined?(::Sidekiq)

        ::Sidekiq.redis { |conn| conn.ping == "PONG" }
      rescue StandardError
        false
      end
    end
  end
end
