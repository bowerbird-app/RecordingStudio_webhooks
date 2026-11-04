# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Minitest::Test
  def test_log_fail_closed_records_class_and_context_not_the_message
    logged = []
    logger = Object.new
    logger.define_singleton_method(:warn) { |message| logged << message }

    Rails.stub(:logger, logger) do
      RecordingStudioWebhooks.log_fail_closed(
        RuntimeError.new("rswh_super-secret-token"),
        context: "inbound_intake"
      )
    end

    assert_equal 1, logged.size
    assert_includes logged.first, "[recording_studio_webhooks] inbound_intake: RuntimeError"
    refute_includes logged.first, "rswh_super-secret-token"
    refute_includes logged.first, "secret"
  end
end
