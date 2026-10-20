# frozen_string_literal: true

require_relative "test_helper"

class EngineAdminHostRouteTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_engine_admin_pages_do_not_call_host_recording_studio_admin_webhooks_path
    views = Dir[File.join(ROOT, "app/views/recording_studio_webhooks/admin/**/*.{erb,rb}")]
    controllers = Dir[File.join(ROOT, "app/controllers/recording_studio_webhooks/admin/**/*.rb")]
    helpers = Dir[File.join(ROOT, "app/helpers/**/*.rb")]

    (views + controllers + helpers).each do |path|
      refute_includes File.read(path), "recording_studio_admin_webhooks_path",
                      "#{path} must not call a host recording_studio_admin_webhooks_path"
    end
  end
end
