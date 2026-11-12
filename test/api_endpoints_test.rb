# frozen_string_literal: true

require "test_helper"

class ApiEndpointsTest < Minitest::Test
  def test_named_endpoints_register_when_recording_studio_api_is_loaded
    skip "Recording Studio API is optional" unless defined?(::RecordingStudioApi)

    RecordingStudioWebhooks::Api::Endpoints.register!
    [
      RecordingStudioWebhooks::Api::Endpoints::INDEX,
      RecordingStudioWebhooks::Api::Endpoints::SHOW,
      RecordingStudioWebhooks::Api::Endpoints::CREATE,
      RecordingStudioWebhooks::Api::Endpoints::UPDATE,
      RecordingStudioWebhooks::Api::Endpoints::ISSUE,
      RecordingStudioWebhooks::Api::Endpoints::REVOKE
    ].each do |name|
      assert RecordingStudioApi.registered_endpoint(name), "#{name} should be registered"
    end
  end

  def test_named_endpoints_register_is_a_no_op_without_recording_studio_api
    skip if defined?(::RecordingStudioApi)

    assert_nil RecordingStudioWebhooks::Api::Endpoints.register!
  end
end
