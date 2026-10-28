# frozen_string_literal: true

require "test_helper"
require "i18n"
require "yaml"

class LocalesTest < Minitest::Test
  # rubocop:disable Style/FormatStringToken -- I18n interpolation tokens match en.yml
  EXPECTED_ENGLISH = {
    "flashes.endpoint_created" => "Endpoint created.",
    "flashes.endpoint_updated" => "Endpoint updated.",
    "flashes.token_issued" => "Token issued.",
    "flashes.token_revoked" => "Token revoked.",
    "flashes.requires_flat_pack" => "Recording Studio Webhooks administration requires FlatPack.",
    "form_errors.choose_registered_provider" => "Choose a registered provider.",
    "form_errors.choose_valid_endpoint" => "Choose a valid endpoint.",
    "form_errors.token_could_not_be_issued" => "The token could not be issued.",
    "form_errors.provide_json_payload" => "Provide a JSON payload and a valid event type.",
    "form_errors.json_object" => "%{label} must be a JSON object."
  }.freeze
  # rubocop:enable Style/FormatStringToken

  def setup
    @previous_load_path = I18n.load_path.dup
    @previous_backend = I18n.backend
    @previous_locale = I18n.locale
    I18n.backend = I18n::Backend::Simple.new
    I18n.backend.load_translations(*Dir[File.join(engine_locales_dir, "*.yml")])
    I18n.locale = :en
  end

  def teardown
    I18n.backend = @previous_backend
    I18n.locale = @previous_locale
    assert_equal @previous_load_path, I18n.load_path,
                 "locales tests must not mutate I18n.load_path"
  end

  def test_engine_ships_only_english_locale_files
    files = Dir[File.join(engine_locales_dir, "*")].map { |path| File.basename(path) }

    assert_equal ["en.yml"], files.sort
  end

  def test_rails_i18n_load_path_includes_the_gem_english_locale_file
    locale_path = File.expand_path(File.join(engine_locales_dir, "en.yml"))
    existent = RecordingStudioWebhooks::Engine.paths["config/locales"].existent.map do |path|
      File.expand_path(path)
    end

    assert_includes existent, locale_path
  end

  def test_lib_sources_do_not_append_i18n_load_path
    lib_root = File.expand_path("../lib", __dir__)
    ruby_files = Dir[File.join(lib_root, "**", "*.rb")]

    refute_empty ruby_files, "expected lib/**/*.rb files to scan"

    ruby_files.each do |path|
      source = File.read(path)

      refute_includes source, "i18n.load_path", "#{path} must not touch i18n.load_path"
      refute_includes source, "I18n.load_path", "#{path} must not touch I18n.load_path"
    end
  end

  def test_copy_resolves_every_english_key_with_and_without_default
    EXPECTED_ENGLISH.each do |key, english|
      assert_equal english, RecordingStudioWebhooks::Copy.t(key),
                   "Copy.t(#{key.inspect}) without default"
      assert_equal english, RecordingStudioWebhooks::Copy.t(key, default: english),
                   "Copy.t(#{key.inspect}) with English default"
    end
  end

  def test_json_object_form_error_interpolates_label
    assert_equal(
      "Identity must be a JSON object.",
      RecordingStudioWebhooks::Copy.t(
        "form_errors.json_object",
        label: "Identity",
        default: "Identity must be a JSON object."
      )
    )
  end

  def test_yes_no_on_off_keys_are_quoted_when_present
    tree = YAML.safe_load_file(File.join(engine_locales_dir, "en.yml"), aliases: true)
    sensitive = %w[yes no on off true false null]
    found = collect_sensitive_keys(tree, sensitive)

    found.each do |key_path|
      value = RecordingStudioWebhooks::Copy.t(key_path)
      refute_nil value
      refute_equal false, value
      refute_equal true, value
    end
  end

  private

  def engine_locales_dir
    File.expand_path("../config/locales", __dir__)
  end

  def collect_sensitive_keys(node, sensitive, prefix = nil)
    return [] unless node.is_a?(Hash)

    node.flat_map do |key, value|
      segment = key.to_s
      path = prefix ? "#{prefix}.#{segment}" : segment
      nested = collect_sensitive_keys(value, sensitive, path)
      sensitive.include?(segment) ? nested + [path.sub(/\Arecording_studio\.webhooks\./, "")] : nested
    end
  end
end
