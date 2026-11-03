# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rails/test_help"

module FlatpackDateRangeFilterAssertions
  def assert_flatpack_date_range_one_submit_path(html, expected_preset:)
    document = Nokogiri::HTML(html)

    refute_includes html, "recording-studio-webhooks--date-range-filter"
    refute_includes html, "recordingStudioWebhooksDateSubmitQueued"

    pickers = document.css("[data-controller~='flat-pack--flatpack-date-picker']")
    assert_operator pickers.size, :>=, 1

    pickers.each do |picker|
      preset_fields = picker.css(
        "input[type='hidden'][data-flat-pack--flatpack-date-picker-target='presetKeyField']"
      )
      assert_equal 1, preset_fields.size
      assert_equal "date_range_preset", preset_fields.first["name"]
      assert_equal expected_preset, preset_fields.first["value"]
      assert_equal 1, picker.css("input[type='hidden'][name='date_range_preset']").size
      refute_includes picker.to_html, "recording-studio-webhooks"
    end

    forms = document.css("form[data-controller~='flat-pack--auto-submit']")
    assert_operator forms.size, :>=, 1
    forms.each do |form|
      assert_includes form["data-action"].to_s, "change->flat-pack--auto-submit#queueSubmit"
      refute_includes form["data-action"].to_s, "recording-studio-webhooks"
    end
  end
end

class ActionDispatch::IntegrationTest
  include FlatpackDateRangeFilterAssertions
end
