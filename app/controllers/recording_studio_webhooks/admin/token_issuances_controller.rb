# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class TokenIssuancesController < BaseController
      before_action :authorize_admin_webhooks_write!, only: :create

      def new
        load_provider_and_endpoints
      end

      def create
        endpoint = filtered_endpoint_scope.find(token_issuance_params.fetch(:endpoint_id))
        endpoint.issue_token!(
          expires_at: parsed_expiration,
          actor: current_admin_actor
        )

        redirect_to "/admin/screens/tokens", notice: "Token issued."
      rescue KeyError, ActiveRecord::RecordNotFound
        load_provider_and_endpoints
        @form_error = "Choose a valid endpoint."
        render :new, status: :unprocessable_entity
      rescue ArgumentError, ActiveRecord::RecordInvalid
        load_provider_and_endpoints
        @form_error = "The token could not be issued."
        render :new, status: :unprocessable_entity
      end

      private

      def token_issuance_params
        params.require(:token_issuance).permit(:provider_name, :endpoint_id, :expires_at)
      end

      def load_provider_and_endpoints
        @providers = available_providers
        @selected_provider = selected_provider
        @endpoints = filtered_endpoint_scope.order(:provider_name, :label)
      end

      def selected_provider
        candidate = params[:provider].presence || params.dig(:token_issuance, :provider_name).presence
        return available_providers.first if candidate.blank?

        available_providers.include?(candidate) ? candidate : available_providers.first
      end

      def available_providers
        @providers ||= endpoint_scope.current.distinct.order(:provider_name).pluck(:provider_name)
      end

      def filtered_endpoint_scope
        scope = endpoint_scope.current
        return scope.none if selected_provider.blank?

        scope.where(provider_name: selected_provider)
      end

      def parsed_expiration
        value = token_issuance_params[:expires_at].to_s.strip
        return nil if value.empty?

        Time.zone.parse(value).tap do |parsed|
          raise ArgumentError if parsed.nil? || parsed <= Time.current
        end
      end
    end
  end
end
