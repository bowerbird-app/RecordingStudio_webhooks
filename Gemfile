# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# recording_studio is not published to RubyGems; resolve the gemspec pin from GitHub.
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v7.7.1"
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.378"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.54.1"
gem "recording_studio_admin", github: "bowerbird-app/RecordingStudio_admin", tag: "v2.19.0"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.9.2"
# Admin requires Logs. It is not published to RubyGems.
gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.8.1", require: false
# Admin and Accessible load Trashable query helpers only; pin for Bundler.
gem "recording_studio_trashable",
    github: "bowerbird-app/RecordingStudio_trashable", tag: "v1.2.1",
    require: false

group :development, :test do
  gem "debug"
  gem "minitest-mock"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
