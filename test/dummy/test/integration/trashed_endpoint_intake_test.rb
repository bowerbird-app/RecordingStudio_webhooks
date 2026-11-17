# frozen_string_literal: true

require "test_helper"

class TrashedEndpointIntakeTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
    workspace = Workspace.create!(name: "Kept intake #{SecureRandom.hex(4)}")
    @root = RecordingStudio.create_root_recording!(workspace, actor: @user)
    owner = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @user)
    raise owner.error if owner.failure?

    @endpoint = RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(
        recording_studio_recording_id: @root.id,
        label: "Kept intake endpoint",
        provider_name: "demo",
        identity: { "test" => true },
        metadata: {},
        policy_overrides: {}
      ),
      actor: @user
    )
    @issued = @endpoint.issue_token!(actor: @user)
    @plaintext = @issued.plaintext_token
    @endpoint_recording = @endpoint.recording_studio_recording
    @token_recording = RecordingStudio::Recording.find_by!(
      recordable_type: "RecordingStudioWebhooks::EndpointToken",
      recordable_id: @issued.endpoint_token.id
    )
  end

  test "a kept token is accepted, then rejected when the endpoint or root recording is not kept" do
    assert_accepted("evt_kept")
    assert_predicate @issued.endpoint_token, :current?

    trash(@endpoint_recording)
    assert_predicate @token_recording.reload, :kept?
    assert_predicate @root.reload, :kept?
    assert_rejected("evt_endpoint_trashed")

    restore(@endpoint_recording)
    assert_accepted("evt_endpoint_restored")
    assert_predicate @issued.endpoint_token.reload, :current?

    trash(@root)
    assert_predicate @endpoint_recording.reload, :kept?
    assert_predicate @token_recording.reload, :kept?
    assert_rejected("evt_root_trashed")
  end

  test "a token whose own recording is not kept is rejected and accepted again after restore" do
    trash(@token_recording)
    assert_predicate @endpoint_recording.reload, :kept?
    assert_predicate @root.reload, :kept?
    assert_rejected("evt_token_trashed")

    restore(@token_recording)
    assert_accepted("evt_token_restored")
  end

  private

  def trash(recording)
    recording.update_columns(trashed_at: Time.current, updated_at: Time.current)
    refute_predicate recording.reload, :kept?
  end

  def restore(recording)
    recording.update_columns(trashed_at: nil, updated_at: Time.current)
    assert_predicate recording.reload, :kept?
  end

  def assert_accepted(event_id)
    post intake_path, params: JSON.generate(id: event_id, type: "demo.received"), headers: intake_headers

    assert_response :accepted
    assert_equal "accepted", response.parsed_body.fetch("status")
    assert_equal @issued.endpoint_token, RecordingStudioWebhooks::EndpointToken.authenticate(plaintext: @plaintext)
  end

  def assert_rejected(event_id)
    post intake_path, params: JSON.generate(id: event_id, type: "demo.received"), headers: intake_headers

    assert_response :unauthorized
    assert_equal({ "status" => "unauthorized" }, response.parsed_body)
    refute_includes response.body.downcase, "trash"
    assert_nil RecordingStudioWebhooks::EndpointToken.authenticate(plaintext: @plaintext)
    refute_predicate @issued.endpoint_token.reload, :current?
    assert_nil @endpoint.inbound_events.find_by(provider_event_id: event_id)

    result = RecordingStudioWebhooks::InboundIntake.call(
      token: @plaintext,
      raw_payload: JSON.generate(id: event_id, type: "demo.received"),
      content_type: "application/json"
    )
    assert_equal 401, result.status
    assert_includes %w[token_invalid endpoint_disabled], result.code
  end

  def intake_path
    "/webhooks/inbound"
  end

  def intake_headers
    {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer #{@plaintext}"
    }
  end
end
