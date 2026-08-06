# frozen_string_literal: true

# app/models/recording_studio_webhooks/application_record.rb
module RecordingStudioWebhooks
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
