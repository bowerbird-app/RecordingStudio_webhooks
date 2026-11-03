# frozen_string_literal: true

require_relative "test_helper"

class DateRangeFilterTest < Minitest::Test
  def test_filter_fields_use_flatpack_preset_name_and_drop_the_apply_handler
    filter_fields = File.read(
      File.expand_path("../app/views/recording_studio_admin/screens/_filter_fields.html.erb", __dir__)
    )
    engine_controller = File.expand_path(
      "../app/javascript/recording_studio_webhooks/controllers/date_range_filter_controller.js",
      __dir__
    )
    dummy_controller = File.expand_path(
      "../test/dummy/app/javascript/controllers/recording_studio_webhooks/date_range_filter_controller.js",
      __dir__
    )

    assert_includes filter_fields, "preset_name: filter.preset_param"
    refute_includes filter_fields, "hidden_field_tag filter.preset_param"
    refute_includes filter_fields, "recording-studio-webhooks--date-range-filter"
    refute_includes filter_fields, "queueDateRangeSubmit"
    refute File.exist?(engine_controller)
    refute File.exist?(dummy_controller)
  end
end
