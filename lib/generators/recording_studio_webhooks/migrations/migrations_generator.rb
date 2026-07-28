# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RecordingStudioWebhooks
  module Generators
    class MigrationsGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Copies the four Recording Studio Webhooks UUID tables into the host application."

      class_option :skip_existing,
        type: :boolean,
        default: true,
        desc: "Do not create a second copy of the engine migration"

      def copy_migration
        if options[:skip_existing] && migration_exists?
          say "skip  create_recording_studio_webhooks_tables.rb (already exists)", :yellow
          return
        end

        migration_template "create_recording_studio_webhooks_tables.rb.tt",
          "db/migrate/create_recording_studio_webhooks_tables.rb"
      end

      private

      def migration_exists?
        Dir.glob(
          File.join(destination_root, "db/migrate", "*_create_recording_studio_webhooks_tables.rb")
        ).any?
      end
    end
  end
end
