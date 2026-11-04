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
        if options[:skip_existing] && create_migration_exists?
          say "skip  create_recording_studio_webhooks_tables.rb (already exists)", :yellow
        else
          migration_template "create_recording_studio_webhooks_tables.rb.tt",
                             "db/migrate/create_recording_studio_webhooks_tables.rb"
        end

        if remove_plaintext_token_migration_exists?
          say "skip  remove_plaintext_token_from_endpoint_tokens.rb (already exists)", :yellow
        else
          migration_template "remove_plaintext_token_from_endpoint_tokens.rb.tt",
                             "db/migrate/remove_plaintext_token_from_endpoint_tokens.rb"
        end
      end

      private

      def create_migration_exists?
        Dir.glob(
          File.join(destination_root, "db/migrate", "*_create_recording_studio_webhooks_tables.rb")
        ).any?
      end

      def remove_plaintext_token_migration_exists?
        Dir.glob(
          File.join(destination_root, "db/migrate", "*_remove_plaintext_token_from_endpoint_tokens.rb")
        ).any?
      end
    end
  end
end
