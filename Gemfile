# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# recording_studio is not published to RubyGems; resolve the gemspec pin from GitHub.
gem "recording_studio", "~> 7.8", github: "bowerbird-app/RecordingStudio", tag: "v7.8.0"
gem "flat_pack", "~> 0.2", github: "bowerbird-app/flatpack", tag: "v0.2.0"
gem "recording_studio_accessible", "~> 0.56", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.56.0"
gem "recording_studio_admin", "~> 2.19", github: "bowerbird-app/RecordingStudio_admin", tag: "v2.19.1"
gem "recording_studio_metrics", "~> 0.10", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.10.0"
# Admin requires Logs. It is not published to RubyGems.
gem "recording_studio_logs", "~> 0.8", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.8.2", require: false
# Admin loads Trashable query helpers only; pin for Bundler.
gem "recording_studio_trashable", "~> 1.2",
    github: "bowerbird-app/RecordingStudio_trashable", tag: "v1.2.3",
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
