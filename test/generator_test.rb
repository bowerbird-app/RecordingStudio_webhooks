# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_webhooks/install/install_generator"
require "generators/recording_studio_webhooks/migrations/migrations_generator"

class GeneratorTest < Minitest::Test
  def test_install_generator_mounts_the_renamed_engine_at_a_safe_path
    generator = RecordingStudioWebhooks::Generators::InstallGenerator.new(
      [],
      { mount_path: "/addons/webhooks" },
      destination_root: Dir.pwd
    )
    routes = []

    generator.stub(:route, ->(statement) { routes << statement }) do
      generator.mount_engine
    end

    assert_equal [
      'mount RecordingStudioWebhooks::Engine, at: "/addons/webhooks", as: "recording_studio_webhooks"'
    ], routes
  end

  def test_install_generator_rejects_unsafe_mount_paths
    generator = RecordingStudioWebhooks::Generators::InstallGenerator.new(
      [],
      { mount_path: "/webhooks/../private" },
      destination_root: Dir.pwd
    )

    assert_raises(Thor::Error) { generator.validate_mount_path }
  end

  def test_migration_template_creates_exactly_four_uuid_tables
    template = File.read(
      File.expand_path(
        "../lib/generators/recording_studio_webhooks/migrations/templates/create_recording_studio_webhooks_tables.rb.tt",
        __dir__
      )
    )

    assert_equal 4, template.scan("create_table :recording_studio_webhooks_").size
    assert_equal 4, template.scan("id: :uuid").size
    assert_includes template, "recording_studio_recordings"
    assert_includes template, "recording_studio_webhooks_action_attempts"
    assert_includes template, "%i[provider_name recording_studio_recording_id]"
    refute_includes template, "superseded_at IS NULL"
    refute_match(/t\.string :token\b/, template)
  end

  def test_remove_plaintext_token_migration_template_drops_token_when_present
    template = File.read(
      File.expand_path(
        "../lib/generators/recording_studio_webhooks/migrations/templates/remove_plaintext_token_from_endpoint_tokens.rb.tt",
        __dir__
      )
    )

    refute_includes template, "TokenDigest"
    assert_includes template, "return unless column_exists?(table, :token)"
    assert_includes template, "remove_column table, :token"
    assert_includes template, "Irreversible for data"
  end

  def test_create_tables_template_indents_digest_with_the_other_columns
    template = File.read(
      File.expand_path(
        "../lib/generators/recording_studio_webhooks/migrations/templates/create_recording_studio_webhooks_tables.rb.tt",
        __dir__
      )
    )

    assert_includes template, "      t.string :digest, null: false\n"
    refute_includes template, "        t.string :digest"
  end

  def test_skip_existing_create_tables_still_copies_the_drop_token_migration
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "db/migrate"))
      File.write(
        File.join(dir, "db/migrate", "20240101000000_create_recording_studio_webhooks_tables.rb"),
        "# existing\n"
      )

      generator = RecordingStudioWebhooks::Generators::MigrationsGenerator.new(
        [],
        { skip_existing: true },
        destination_root: dir
      )
      templates = []
      generator.stub(:migration_template, ->(source, dest) { templates << [source, dest] }) do
        generator.copy_migration
        generator.copy_remove_plaintext_token_migration
      end

      assert_equal [
        [
          "remove_plaintext_token_from_endpoint_tokens.rb.tt",
          "db/migrate/remove_plaintext_token_from_endpoint_tokens.rb"
        ]
      ], templates
    end
  end
end
