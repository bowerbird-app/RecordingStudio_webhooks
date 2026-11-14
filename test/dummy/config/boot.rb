ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# `bin/rails test` boots the app (test:prepare) before test_helper runs.
# Start coverage here so engine files loaded during boot are counted.
if ENV["RAILS_ENV"] == "test" && ENV["DISABLE_SIMPLECOV"] != "true"
  ENV["SIMPLECOV_COMMAND_NAME"] ||= "dummy"
  require_relative "../../simplecov_helper"
end
# require "bootsnap/setup" # Speed up boot time by caching expensive operations.
