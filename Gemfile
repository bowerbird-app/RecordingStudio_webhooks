# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# recording_studio is not published to RubyGems; resolve the gemspec pin from GitHub.
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v4.2.2"
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.198"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.11.1"
# Admin stays on the unpublished 4.2 branch: v2.0.4 does not contain
# 51579fa59545a28b62d710a4547b9f062b8ea46a (merge-base --is-ancestor is false).
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
