# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class ActionPlansController < BaseController
      before_action :load_endpoint
      before_action :load_event
      before_action :load_action_plan

      def show
      end

      private

      def load_event
        @event = @endpoint.inbound_events.find(params[:event_id])
      rescue ActiveRecord::RecordNotFound
        raise ActionController::RoutingError, "Not Found"
      end

      def load_action_plan
        @action_plan = @event.action_plans.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        raise ActionController::RoutingError, "Not Found"
      end
    end
  end
end
