# frozen_string_literal: true

module RecordingStudioWebhooks
  module AdminLast4WeeksPatch
    module DateRangeFilter
      private

      # Keep "last_4_weeks" aligned with FlatPack's 28-day inclusive preset.
      def range_for_preset(key)
        normalized_key = key.to_s.strip.downcase.to_sym
        if normalized_key == :last_4_weeks
          end_date = Date.current
          start_date = end_date - 27.days
          return RecordingStudioAdmin::Filters::DateRangeFilter::RangeValue.new(start_date, end_date, normalized_key)
        end

        super
      end
    end
  end
end