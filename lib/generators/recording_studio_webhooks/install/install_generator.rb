# frozen_string_literal: true

require "rails/generators"

module RecordingStudioWebhooks
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :mount_path,
        type: :string,
        default: "/recording_studio_webhooks",
        desc: "Path at which to mount the engine"
      class_option :skip_migrations,
        type: :boolean,
        default: false,
        desc: "Do not generate the engine migration"

      def validate_mount_path
        valid = mount_path.match?(%r{\A/[a-z0-9][a-z0-9_/-]*\z})
        return if valid && !mount_path.include?("..") && !mount_path.include?("//")

        raise Thor::Error, "mount path must be a non-root, lowercase absolute URL path"
      end

      def create_initializer
        template "recording_studio_webhooks.rb.tt",
          "config/initializers/recording_studio_webhooks.rb"
      end

      def mount_engine
        routes_file = "config/routes.rb"
        mount_statement = "mount RecordingStudioWebhooks::Engine, at: #{mount_path.inspect}, as: \"recording_studio_webhooks\""
        destination_routes = File.join(destination_root, routes_file)
        return if File.exist?(destination_routes) && File.read(destination_routes).include?(mount_statement)

        route mount_statement
      end

      def install_migrations
        invoke "recording_studio_webhooks:migrations" unless options[:skip_migrations]
      end

      private

      def mount_path
        @mount_path ||= options.fetch(:mount_path).to_s.sub(%r{/+\z}, "").presence || "/"
      end
    end
  end
end
