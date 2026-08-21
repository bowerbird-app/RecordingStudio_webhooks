# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# recording_studio is not published to RubyGems; resolve the gemspec pin from GitHub.
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v4.2.0"
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.133"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.6.1"
# Admin 2.0.0 is the 4.2-compatible line; no tag yet as of 2026-08-21.
gem "recording_studio_admin", github: "bowerbird-app/RecordingStudio_admin",
                              branch: "cursor/rs41-accessible-06-upgrade-eb59"

group :development, :test do
  gem "debug"
  gem "minitest-mock"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
