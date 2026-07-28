# frozen_string_literal: true

require "test_helper"

class DispatcherTest < Minitest::Test
  def test_custom_dispatcher_receives_only_plan_identifier_and_schedule
    with_fresh_configuration do |configuration|
      calls = []
      configuration.dispatcher = ->(plan_id, wait_until) { calls << [plan_id, wait_until] }
      scheduled_for = Time.utc(2026, 7, 28, 12, 0, 0)

      RecordingStudioWebhooks::Dispatcher.enqueue("plan-uuid", wait_until: scheduled_for)

      assert_equal [["plan-uuid", scheduled_for]], calls
    end
  end

  def test_custom_keyword_dispatcher_is_supported
    with_fresh_configuration do |configuration|
      calls = []
      configuration.dispatcher = ->(plan_id, wait_until:) { calls << { id: plan_id, at: wait_until } }

      RecordingStudioWebhooks::Dispatcher.enqueue("plan-uuid")

      assert_equal [{ id: "plan-uuid", at: nil }], calls
    end
  end
end
