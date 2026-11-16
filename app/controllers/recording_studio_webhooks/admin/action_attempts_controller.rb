# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class ActionAttemptsController < BaseController
      before_action :load_endpoint, if: -> { params[:endpoint_id].present? }
      before_action :load_event, if: -> { params[:event_id].present? }
      before_action :load_action_attempt

      def show; end

      private

      def load_event
        @event = InboundEvent.where(endpoint_id: endpoint_revision_ids(@endpoint)).find(params[:event_id])
      rescue ActiveRecord::RecordNotFound
        raise ActionController::RoutingError, "Not Found"
      end

      def load_action_attempt
        @action_attempt = if @event
                            @event.action_attempts.find(params[:id])
                          else
                            scoped_action_attempt
                          end
        @event ||= @action_attempt.inbound_event
        @endpoint ||= @event.endpoint
      rescue ActiveRecord::RecordNotFound
        raise ActionController::RoutingError, "Not Found"
      end

      def scoped_action_attempt
        ActionAttempt.joins(inbound_event: :endpoint)
                     .where(recording_studio_webhooks_endpoints: { id: endpoint_scope.select(:id) })
                     .find(params[:id])
      end
    end
  end
end
