# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class EndpointsController < BaseController
      before_action :load_endpoint, only: %i[show edit update]

      def index
        @endpoints = endpoint_scope.includes(:recording, :endpoint_tokens).order(created_at: :desc)
      end

      def new
        @endpoint = Endpoint.new(enabled: true, identity: {}, metadata: {}, policy_overrides: {})
      end

      def create
        @endpoint = Endpoint.new(endpoint_attributes)
        @endpoint.recording_studio_recording_id = selected_recording.id

        if @form_error.nil? && registered_provider? && @endpoint.save
          @endpoint.audit!(
            action: "recording_studio_webhooks.endpoint.created",
            actor: current_admin_actor,
            metadata: { endpoint_id: @endpoint.id }
          )
          redirect_to admin_endpoint_path(@endpoint), notice: "Endpoint created."
        else
          @form_error ||= "Choose a registered provider." unless registered_provider?
          render :new, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        raise ActionController::RoutingError, "Not Found"
      end

      def show
        @tokens = @endpoint.endpoint_tokens.order(created_at: :desc)
        @events = @endpoint.inbound_events.includes(:action_plans).order(received_at: :desc).limit(20)
      end

      def edit
      end

      def update
        if @form_error.nil? && @endpoint.update(endpoint_update_attributes)
          @endpoint.audit!(
            action: "recording_studio_webhooks.endpoint.revised",
            actor: current_admin_actor,
            metadata: { endpoint_id: @endpoint.id }
          )
          redirect_to admin_endpoint_path(@endpoint), notice: "Endpoint updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def selected_recording
        available_recordings.find(params.require(:endpoint).fetch(:recording_studio_recording_id))
      end

      def endpoint_attributes
        fields = endpoint_fields
        {
          provider_name: fields[:provider_name],
          identity_key: fields[:identity_key],
          enabled: cast_boolean(fields[:enabled]),
          identity: parsed_json_object(fields[:identity_json], "identity"),
          metadata: parsed_json_object(fields[:metadata_json], "metadata"),
          policy_overrides: parsed_json_object(fields[:policy_json], "policy")
        }
      end

      def endpoint_update_attributes
        fields = endpoint_fields
        {
          enabled: cast_boolean(fields[:enabled]),
          metadata: parsed_json_object(fields[:metadata_json], "metadata"),
          policy_overrides: parsed_json_object(fields[:policy_json], "policy")
        }
      end

      def endpoint_fields
        params.require(:endpoint).permit(
          :recording_studio_recording_id,
          :provider_name,
          :identity_key,
          :enabled,
          :identity_json,
          :metadata_json,
          :policy_json
        )
      end

      def parsed_json_object(value, label)
        text = value.to_s.strip
        return {} if text.empty?

        parsed = JSON.parse(text)
        raise JSON::ParserError unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError
        @form_error = "#{label.capitalize} must be a JSON object."
        {}
      end

      def cast_boolean(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end

      def registered_provider?
        webhook_configuration.providers.fetch(@endpoint.provider_name).present?
      end
    end
  end
end
