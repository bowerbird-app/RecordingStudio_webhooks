ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require_relative "../../support/widen_recording_studio_requirement"
require "bundler/setup" # Set up gems listed in the Gemfile.
# require "bootsnap/setup" # Speed up boot time by caching expensive operations.
