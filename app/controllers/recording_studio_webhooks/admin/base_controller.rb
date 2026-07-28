# frozen_string_literal: true

module RecordingStudioWebhooks
  module Admin
    class BaseController < ApplicationController
      AdminContext = Struct.new(:controller, :actor, keyword_init: true)

      before_action :require_admin!
      before_action :require_flat_pack!

      helper_method :available_recordings, :webhook_configuration

      private

      def require_admin!
        return if admin_authorized?

        raise ActionController::RoutingError, "Not Found"
      end

      def admin_authorized?
        authorizer = webhook_configuration.admin_authorizer
        return false unless authorizer

        invoke_callable(authorizer, admin_context) == true
      rescue StandardError
        false
      end

      # FlatPack is supplied by Recording Studio host UI bundles rather than
      # RubyGems. Fail before rendering a partial if a host omitted it, instead
      # of surfacing an unhelpful uninitialized-constant exception.
      def require_flat_pack!
        return if defined?(::FlatPack)

        render plain: "Recording Studio Webhooks administration requires FlatPack.", status: :service_unavailable
      end

      def admin_context
        @admin_context ||= AdminContext.new(controller: self, actor: current_admin_actor)
      end

      def current_admin_actor
        return unless respond_to?(:current_user, true)

        send(:current_user)
      end

      def available_recordings
        @available_recordings ||= begin
          return empty_recording_scope unless defined?(::RecordingStudio::Recording)

          scope = ::RecordingStudio::Recording.all
          resolver = webhook_configuration.admin_recording_scope
          return scope unless resolver

          scoped = invoke_callable(resolver, admin_context)
          normalize_recording_scope(scope, scoped)
        rescue StandardError
          empty_recording_scope
        end
      end

      def endpoint_scope
        Endpoint.where(recording_studio_recording_id: available_recordings.select(:id))
      end

      def load_endpoint
        @endpoint = endpoint_scope.find_by!(id: params[:endpoint_id] || params[:id])
      end

      def invoke_callable(callable, context)
        parameters = callable.respond_to?(:parameters) ? callable.parameters : []
        keyword_names = parameters.filter_map do |kind, name|
          name if %i[key keyreq].include?(kind)
        end

        if parameters.any? { |kind, _| kind == :keyrest }
          callable.call(context: context, actor: context.actor, controller: self)
        elsif keyword_names.any?
          callable.call(**{ context: context, actor: context.actor, controller: self }.slice(*keyword_names))
        elsif callable.respond_to?(:arity) && callable.arity.zero?
          callable.call
        else
          callable.call(context)
        end
      end

      def normalize_recording_scope(scope, value)
        return value if value.is_a?(ActiveRecord::Relation) && value.klass <= ::RecordingStudio::Recording

        ids = Array(value).filter_map { |recording| recording.respond_to?(:id) ? recording.id : recording }
        scope.where(id: ids)
      end

      def empty_recording_scope
        return ::RecordingStudio::Recording.none if defined?(::RecordingStudio::Recording)

        Endpoint.none
      end
    end
  end
end
