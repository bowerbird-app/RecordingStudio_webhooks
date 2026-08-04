# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class EndpointsController < BaseController
      before_action :load_endpoint, only: :update
      before_action :authorize_admin_webhooks_write!, only: %i[create update]

      def index
        redirect_to "/admin/screens/endpoints#{"?#{request.query_string}" if request.query_string.present?}"
      end

      def new
        @endpoint = Endpoint.new(enabled: true, identity: {}, metadata: {}, policy_overrides: {})
      end

      def create
        @endpoint = Endpoint.new(endpoint_attributes)
        @endpoint.recording_studio_recording_id = selected_recording.id

        if @form_error.nil? && registered_provider?
          Endpoint.transaction do
            @endpoint = EndpointLifecycle.create!(endpoint: @endpoint, actor: current_admin_actor)
            @endpoint.issue_token!(actor: current_admin_actor)
          end

          redirect_to "/admin/screens/endpoints", notice: "Endpoint created."
        else
          @form_error ||= "Choose a registered provider." unless registered_provider?
          render :new, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordInvalid
        render :new, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound
        raise ActionController::RoutingError, "Not Found"
      end

      def update
        attributes = endpoint_update_attributes
        if @form_error.nil?
          @endpoint = EndpointLifecycle.update!(
            endpoint: @endpoint,
            attributes: attributes,
            actor: current_admin_actor
          )
          if params[:auto_save].to_s == "1"
            redirect_to safe_return_to_path(params[:return_to]) || "/admin/screens/endpoints"
          else
            redirect_to "/admin/screens/endpoints", notice: "Endpoint updated."
          end
        else
          redirect_to "/admin/screens/endpoints", alert: @form_error
        end
      rescue ActiveRecord::RecordInvalid
        redirect_to "/admin/screens/endpoints", alert: @endpoint.errors.full_messages.to_sentence
      end

      private

      def selected_recording
        requested_recording_id = endpoint_fields[:recording_studio_recording_id].to_s.strip
        return available_recordings.find(requested_recording_id) if requested_recording_id.present?

        current_root = current_root_recording_for_assignment
        raise ActiveRecord::RecordNotFound unless current_root

        available_recordings.find(current_root.id)
      end

      def current_root_recording_for_assignment
        return unless respond_to?(:current_root_recording, true)

        root = send(:current_root_recording)
        return unless root.present?

        available_recordings.find_by(id: root.id)
      rescue StandardError
        nil
      end

      def endpoint_attributes
        fields = endpoint_fields
        {
          label: fields[:label],
          provider_name: fields[:provider_name],
          enabled: cast_boolean(fields[:enabled]),
          identity: parsed_json_object(fields[:identity_json], "identity"),
          metadata: parsed_json_object(fields[:metadata_json], "metadata"),
          policy_overrides: parsed_json_object(fields[:policy_json], "policy")
        }
      end

      def endpoint_update_attributes
        fields = endpoint_fields
        attributes = {}
        attributes[:label] = fields[:label] if fields.key?(:label)
        attributes[:enabled] = cast_boolean(fields[:enabled]) if fields.key?(:enabled)
        attributes
      end

      def endpoint_fields
        params.require(:endpoint).permit(
          :recording_studio_recording_id,
          :label,
          :provider_name,
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

      def safe_return_to_path(value)
        path = value.to_s.strip
        return nil if path.empty?
        return nil unless path.start_with?("/")
        return nil if path.start_with?("//")

        path
      end

      def registered_provider?
        webhook_configuration.providers.fetch(@endpoint.provider_name).present?
      end
    end
  end
end
