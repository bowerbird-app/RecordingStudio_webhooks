# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_webhooks/install/install_generator"

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
  end
end
