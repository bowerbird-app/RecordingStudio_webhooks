# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require "minitest/autorun"
require "minitest/mock"
require "rails"
require "recording_studio_webhooks"

module RecordingStudioWebhooksTestSupport
  def with_fresh_configuration
    previous = RecordingStudioWebhooks.instance_variable_get(:@configuration)
    configuration = RecordingStudioWebhooks::Configuration.new
    RecordingStudioWebhooks.instance_variable_set(:@configuration, configuration)
    yield configuration
  ensure
    RecordingStudioWebhooks.instance_variable_set(:@configuration, previous)
  end
end

class Minitest::Test
  include RecordingStudioWebhooksTestSupport
end
