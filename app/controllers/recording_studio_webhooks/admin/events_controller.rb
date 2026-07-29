# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class EventsController < BaseController
      before_action :load_endpoint, if: :endpoint_scoped?
      before_action :load_event, only: :show

      def index
        @providers = webhook_configuration.providers.all.sort_by(&:name)
        @endpoints = endpoint_scope.current.order(:provider_name, :label)
        @filter = event_filter_params.to_h.symbolize_keys

        scope = InboundEvent.includes(:action_plans, :endpoint).where(endpoint_id: endpoint_scope.select(:id))
        scope = scope.where(endpoint_id: @endpoint.id) if endpoint_scoped?
        scope = scope.where(provider_name: @filter[:provider_name]) if @filter[:provider_name].present?
        scope = scope.where(endpoint_id: @filter[:endpoint_id]) if @filter[:endpoint_id].present?
        scope = scope.where(endpoint_token_id: @filter[:endpoint_token_id]) if @filter[:endpoint_token_id].present?
        scope = scope.where(event_type: @filter[:event_type]) if @filter[:event_type].present?
        scope = scope.where(status: @filter[:status]) if @filter[:status].present?
        scope = scope.where("received_at >= ?", parsed_from_time) if parsed_from_time
        scope = scope.where("received_at <= ?", parsed_to_time) if parsed_to_time

        if @filter[:execution_mode].present?
          scope = scope.joins(:action_plans)
            .where("recording_studio_webhooks_action_plans.policy_snapshot ->> 'execution_mode' = ?", @filter[:execution_mode])
            .distinct
        end

        @events = scope.order(received_at: :desc).limit(200)
      end

      def show
      end

      private

      def endpoint_scoped?
        params[:endpoint_id].present?
      end

      def load_event
        scope = InboundEvent.includes(:action_plans).where(endpoint_id: endpoint_scope.select(:id))
        scope = scope.where(endpoint_id: @endpoint.id) if endpoint_scoped?
        @event = scope.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        raise ActionController::RoutingError, "Not Found"
      end

      def event_filter_params
        params.permit(
          :provider_name,
          :endpoint_id,
          :endpoint_token_id,
          :event_type,
          :status,
          :execution_mode,
          :from,
          :to
        )
      end

      def parsed_from_time
        parse_time(event_filter_params[:from])
      end

      def parsed_to_time
        parse_time(event_filter_params[:to])
      end

      def parse_time(value)
        raw = value.to_s.strip
        return nil if raw.empty?

        Time.zone.parse(raw)
      rescue ArgumentError
        nil
      end
    end
  end
end
