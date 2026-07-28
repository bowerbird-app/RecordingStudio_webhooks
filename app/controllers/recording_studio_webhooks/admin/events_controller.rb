# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class EventsController < BaseController
      before_action :load_endpoint
      before_action :load_event, only: :show

      def index
        @events = @endpoint.inbound_events.includes(:action_plans).order(received_at: :desc)
      end

      def show
      end

      private

      def load_event
        @event = @endpoint.inbound_events.includes(:action_plans).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        raise ActionController::RoutingError, "Not Found"
      end
    end
  end
end
