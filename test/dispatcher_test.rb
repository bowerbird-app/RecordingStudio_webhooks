# frozen_string_literal: true

require "test_helper"

class DispatcherTest < Minitest::Test
  def test_custom_dispatcher_receives_only_attempt_identifier_and_schedule
    with_fresh_configuration do |configuration|
      calls = []
      configuration.dispatcher = ->(attempt_id, wait_until) { calls << [attempt_id, wait_until] }
      scheduled_for = Time.utc(2026, 7, 28, 12, 0, 0)

      RecordingStudioWebhooks::Dispatcher.enqueue("attempt-uuid", wait_until: scheduled_for)

      assert_equal [["attempt-uuid", scheduled_for]], calls
    end
  end

  def test_custom_keyword_dispatcher_is_supported
    with_fresh_configuration do |configuration|
      calls = []
      configuration.dispatcher = ->(attempt_id, wait_until:) { calls << { id: attempt_id, at: wait_until } }

      RecordingStudioWebhooks::Dispatcher.enqueue("attempt-uuid")

      assert_equal [{ id: "attempt-uuid", at: nil }], calls
    end
  end
end
