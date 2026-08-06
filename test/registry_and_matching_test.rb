# frozen_string_literal: true

require "test_helper"

class RegistryAndMatchingTest < Minitest::Test
  def test_exact_actions_precede_longer_suffix_wildcards_and_names_break_ties
    with_fresh_configuration do |configuration|
      configuration.provider "billing"
      configuration.action "wildcard", ->(_context) {}, provider: "billing", event: "invoice.*"
      configuration.action "nested", ->(_context) {}, provider: "billing", event: "invoice.payment.*"
      configuration.action "exact", ->(_context) {}, provider: "billing", event: "invoice.payment.failed"
      configuration.action "alpha", ->(_context) {}, provider: "billing", event: "invoice.*", priority: 10

      matches = configuration.actions.matching("billing", "invoice.payment.failed")

      assert_equal %w[exact nested alpha wildcard], matches.map(&:name)
      assert_equal "exact", configuration.actions.best_match("billing", "invoice.payment.failed").name
    end
  end

  def test_suffix_wildcard_matches_a_suffix_but_not_the_prefix_itself
    pattern = RecordingStudioWebhooks::EventPattern.new("invoice.*")

    assert pattern.matches?("invoice.paid")
    assert pattern.matches?("invoice.payment.failed")
    refute pattern.matches?("invoice")
    refute pattern.matches?("other.invoice.paid")
  end

  def test_registry_normalizes_names_and_rejects_duplicate_registration
    with_fresh_configuration do |configuration|
      configuration.provider "GitHub"

      assert_equal "github", configuration.providers.fetch("GITHUB").name
      assert_raises(RecordingStudioWebhooks::DuplicateRegistrationError) do
        configuration.provider "github"
      end
    end
  end

  def test_invalid_patterns_are_not_general_globs
    assert_raises(RecordingStudioWebhooks::InvalidEventPatternError) do
      RecordingStudioWebhooks::EventPattern.new("invoice*")
    end
    assert_raises(RecordingStudioWebhooks::InvalidEventPatternError) do
      RecordingStudioWebhooks::EventPattern.new("*.paid")
    end
  end
end
