# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class TokensController < BaseController
      before_action :load_endpoint
      before_action :authorize_admin_webhooks_write!, only: %i[create destroy]

      def index
        @tokens = @endpoint.endpoint_tokens.order(created_at: :desc)
        @events_by_token_id = @endpoint.inbound_events.group(:endpoint_token_id).count
      end

      def create
        issuance = @endpoint.issue_token!(
          expires_at: parsed_expiration,
          metadata: parsed_metadata,
          actor: current_admin_actor
        )
        @issued_token = issuance.plaintext_token
        @endpoint_url = "#{request.base_url}#{inbound_path(provider: @endpoint.provider_name, endpoint_recording_id: @endpoint.recording_studio_recording_id)}"
        response.headers["Cache-Control"] = "no-store, max-age=0"
        response.headers["Pragma"] = "no-cache"
        render :show, status: :created
      rescue ArgumentError, ActiveRecord::RecordInvalid
        @tokens = @endpoint.endpoint_tokens.order(created_at: :desc)
        @events_by_token_id = @endpoint.inbound_events.group(:endpoint_token_id).count
        @form_error = "The token could not be issued."
        render :index, status: :unprocessable_entity
      end

      def destroy
        @endpoint.endpoint_tokens.find(params[:id]).revoke!(actor: current_admin_actor)
        redirect_to admin_endpoint_tokens_path(@endpoint), notice: "Token revoked."
      rescue ActiveRecord::RecordNotFound
        raise ActionController::RoutingError, "Not Found"
      end

      private

      def token_fields
        params.fetch(:endpoint_token, {}).permit(:expires_at, :metadata_json)
      end

      def parsed_expiration
        value = token_fields[:expires_at].to_s.strip
        return nil if value.empty?

        Time.zone.parse(value).tap do |parsed|
          raise ArgumentError if parsed.nil? || parsed <= Time.current
        end
      end

      def parsed_metadata
        value = token_fields[:metadata_json].to_s.strip
        return {} if value.empty?

        parsed = JSON.parse(value)
        raise ArgumentError unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError
        raise ArgumentError
      end
    end
  end
end
