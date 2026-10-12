# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

# Render-level literal-English asserts for wave 2 controller copy. English
# output must match main. Does not rewrite existing tests to expect HOST strings.
class Wave2I18nRenderTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @webhooks_configuration = RecordingStudioWebhooks.configuration
    @original_admin_authorizer = @webhooks_configuration.admin_authorizer
    @original_admin_recording_scope = @webhooks_configuration.admin_recording_scope
    @webhooks_configuration.admin_authorizer = ->(context) { context.actor&.email == "admin@admin.com" }
    @webhooks_configuration.admin_recording_scope = ->(_context) { RecordingStudio::Recording.where(trashed_at: nil) }

    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
    workspace = Workspace.create!(name: "Wave2 I18n Workspace #{SecureRandom.hex(4)}")
    @recording = RecordingStudio.root_recording_for(workspace)
    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: @recording,
      actor: @user
    )
    raise result.error if result.failure?

    @endpoint = RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(
        recording_studio_recording_id: @recording.id,
        label: "Wave2 endpoint",
        provider_name: "demo",
        identity: { "test" => true },
        metadata: {},
        policy_overrides: {}
      ),
      actor: @user
    )
  end

  teardown do
    @webhooks_configuration.admin_authorizer = @original_admin_authorizer
    @webhooks_configuration.admin_recording_scope = @original_admin_recording_scope
  end

  test "revoking a token renders literal english flash notice" do
    sign_in @user
    issuance = @endpoint.issue_token!

    delete "/admin/webhooks/endpoints/#{@endpoint.id}/tokens/#{issuance.endpoint_token.id}"

    assert_redirected_to "/admin/screens/tokens"
    assert_equal "Token revoked.", flash[:notice]
  end

  test "creating an endpoint renders literal english flash notice" do
    sign_in @user

    assert_difference -> { RecordingStudioWebhooks::Endpoint.current.count }, 1 do
      post "/admin/webhooks/endpoints", params: {
        endpoint: {
          recording_studio_recording_id: @recording.id,
          label: "Wave2 created #{SecureRandom.hex(3)}",
          provider_name: "demo",
          enabled: "1",
          identity_json: "{}",
          metadata_json: "{}",
          policy_json: "{}"
        }
      }
    end

    assert_redirected_to "/admin/screens/endpoints"
    assert_equal "Endpoint created.", flash[:notice]
  end

  test "issuing a token renders literal english flash notice" do
    sign_in @user

    post "/admin/webhooks/tokens", params: {
      token_issuance: {
        provider_name: @endpoint.provider_name,
        endpoint_id: @endpoint.id
      }
    }

    assert_redirected_to "/admin/screens/tokens"
    assert_equal "Token issued.", flash[:notice]
  end

  test "bad provider create renders host boot-order override string" do
    sign_in @user

    post "/admin/webhooks/endpoints", params: {
      endpoint: {
        recording_studio_recording_id: @recording.id,
        label: "Bad provider #{SecureRandom.hex(3)}",
        provider_name: "not_a_registered_provider",
        enabled: "1",
        identity_json: "{}",
        metadata_json: "{}",
        policy_json: "{}"
      }
    }

    assert_response :unprocessable_entity
    # Always-loaded dummy host override for this rarely shown key.
    assert_includes response.body, "HOST Choose a registered provider."
  end
end
