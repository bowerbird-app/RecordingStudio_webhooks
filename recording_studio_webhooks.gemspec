# frozen_string_literal: true

require_relative "lib/recording_studio_webhooks/version"

Gem::Specification.new do |spec|
  spec.name        = "recording_studio_webhooks"
  spec.version     = RecordingStudioWebhooks::VERSION
  spec.authors     = ["Bowerbird"]
  spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_webhooks"
  spec.summary     = "Inbound webhook intake and action execution for Recording Studio"
  spec.description = "A mountable Rails engine for securely receiving, deduplicating, and processing inbound webhooks."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bowerbird-app/RecordingStudio_webhooks"
  spec.metadata["changelog_uri"] = "https://github.com/bowerbird-app/RecordingStudio_webhooks/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", "~> 8.1.0"
  spec.add_dependency "recording_studio", "~> 3.0"
  spec.add_dependency "sidekiq", "~> 8.1.6"
end
