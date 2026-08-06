# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "recording_studio/v3.0.0"
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.129"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible"
gem "recording_studio_admin", github: "bowerbird-app/RecordingStudio_admin"

group :development, :test do
  gem "debug"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
