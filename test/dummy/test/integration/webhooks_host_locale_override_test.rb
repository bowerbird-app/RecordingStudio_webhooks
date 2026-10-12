# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class WebhooksHostLocaleOverrideTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  HOST_CHOOSE_PROVIDER = "HOST Choose a registered provider."
  HOST_TOKEN_REVOKED = "HOST Token revoked."
  BOOT_OVERRIDE_KEY = "recording_studio.webhooks.form_errors.choose_registered_provider"
  TOKEN_REVOKED_KEY = "recording_studio.webhooks.flashes.token_revoked"
  BOOT_HOST_LOCALE = Rails.root.join("config/locales/recording_studio_webhooks_host.en.yml")
  FRESH_HOST_LOCALE = Rails.root.join("test/locales/webhooks_host_override.en.yml")

  setup do
    @load_path_before = I18n.load_path.dup
    @backend_before = I18n.backend

    @webhooks_configuration = RecordingStudioWebhooks.configuration
    @original_admin_authorizer = @webhooks_configuration.admin_authorizer
    @original_admin_recording_scope = @webhooks_configuration.admin_recording_scope
    @webhooks_configuration.admin_authorizer = ->(context) { context.actor&.email == "admin@admin.com" }
    @webhooks_configuration.admin_recording_scope = ->(_context) { RecordingStudio::Recording.where(trashed_at: nil) }

    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
  end

  teardown do
    @webhooks_configuration.admin_authorizer = @original_admin_authorizer
    @webhooks_configuration.admin_recording_scope = @original_admin_recording_scope
    I18n.backend = @backend_before if @backend_before
    assert_equal @load_path_before, I18n.load_path,
                 "test must not leave I18n.load_path modified"
  end

  # Real-boot-order guard: host file under config/locales must win without any
  # test-time load_path mutation. Render assertion uses the bad-provider form error.
  test "host locale override for recording_studio.webhooks wins on boot order" do
    assert File.exist?(BOOT_HOST_LOCALE)
    assert_includes File.read(BOOT_HOST_LOCALE), HOST_CHOOSE_PROVIDER
    assert_equal HOST_CHOOSE_PROVIDER, I18n.t(BOOT_OVERRIDE_KEY)
    assert_equal @load_path_before, I18n.load_path,
                 "boot-order test must not mutate I18n.load_path"

    sign_in @user
    workspace = Workspace.create!(name: "Boot Override #{SecureRandom.hex(4)}")
    recording = RecordingStudio.root_recording_for(workspace)
    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: recording,
      actor: @user
    )
    raise result.error if result.failure?

    post "/admin/webhooks/endpoints", params: {
      endpoint: {
        recording_studio_recording_id: recording.id,
        label: "Bad provider #{SecureRandom.hex(3)}",
        provider_name: "not_a_registered_provider",
        enabled: "1",
        identity_json: "{}",
        metadata_json: "{}",
        policy_json: "{}"
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, HOST_CHOOSE_PROVIDER
  end

  # Test-only fixture applied via backend.load_translations(file) on top of the
  # already-initialized backend — never mutates I18n.load_path (Marshal).
  test "fresh-backend last-file-wins host fixture overrides gem english on token revoke" do
    assert File.exist?(FRESH_HOST_LOCALE), "expected test-only host override fixture at #{FRESH_HOST_LOCALE}"
    assert_includes File.read(FRESH_HOST_LOCALE), HOST_TOKEN_REVOKED

    sign_in @user
    workspace = Workspace.create!(name: "Host Override #{SecureRandom.hex(4)}")
    recording = RecordingStudio.root_recording_for(workspace)
    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: recording,
      actor: @user
    )
    raise result.error if result.failure?

    endpoint = RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(
        recording_studio_recording_id: recording.id,
        label: "Host override endpoint",
        provider_name: "demo",
        identity: { "test" => true },
        metadata: {},
        policy_overrides: {}
      ),
      actor: @user
    )
    issuance = endpoint.issue_token!

    snapshot = i18n_backend_translations_snapshot
    I18n.t(TOKEN_REVOKED_KEY)
    I18n.backend.load_translations(FRESH_HOST_LOCALE.to_s)

    assert_equal @load_path_before, I18n.load_path
    assert_equal HOST_TOKEN_REVOKED, I18n.t(TOKEN_REVOKED_KEY)
    assert_equal HOST_CHOOSE_PROVIDER, I18n.t(BOOT_OVERRIDE_KEY)

    delete "/admin/webhooks/endpoints/#{endpoint.id}/tokens/#{issuance.endpoint_token.id}"

    assert_redirected_to "/admin/screens/tokens"
    assert_equal HOST_TOKEN_REVOKED, flash[:notice]
  ensure
    restore_i18n_backend_translations(snapshot) if snapshot
  end

  private

  def i18n_backend_translations_snapshot
    backend = I18n.backend
    backend.send(:init_translations) unless backend.initialized?
    translations =
      if backend.respond_to?(:translations)
        backend.translations
      else
        backend.instance_variable_get(:@translations)
      end
    return unless translations

    deep_plain_copy(translations)
  end

  def restore_i18n_backend_translations(snapshot)
    backend = I18n.backend
    backend.instance_variable_set(:@translations, snapshot)
    backend.instance_variable_set(:@initialized, true) if backend.instance_variable_defined?(:@initialized)
  end

  def deep_plain_copy(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, nested), copy| copy[key] = deep_plain_copy(nested) }
    when Array
      value.map { |nested| deep_plain_copy(nested) }
    else
      value
    end
  end
end
