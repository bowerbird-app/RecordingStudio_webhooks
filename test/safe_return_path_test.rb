# frozen_string_literal: true

require "test_helper"

class SafeReturnPathTest < Minitest::Test
  def test_accepts_a_same_host_relative_path_with_query
    path = "/admin/screens/endpoints?provider=demo"

    assert_equal path, RecordingStudioWebhooks::SafeReturnPath.call(path)
  end

  def test_rejects_protocol_relative_backslash_absolute_and_blank_values
    [
      nil,
      "",
      "   ",
      "//evil.example",
      "/\\evil.example",
      "/admin\\screens",
      "https://evil.example/phish",
      "/admin screens",
      "%2F%2Fevil.example"
    ].each do |value|
      assert_nil RecordingStudioWebhooks::SafeReturnPath.call(value), value.inspect
    end
  end

  def test_rejects_encoded_protocol_relative_paths
    assert_nil RecordingStudioWebhooks::SafeReturnPath.call("/%2Fevil.example")
  end
end
