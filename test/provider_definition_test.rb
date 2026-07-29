# frozen_string_literal: true

require "test_helper"

class ProviderDefinitionTest < Minitest::Test
  def test_callback_accessors_are_readable_after_freeze
    verifier = ->(_env, _raw, _headers) { true }
    type_extractor = ->(payload) { payload.fetch("type") }
    id_extractor = ->(payload) { payload.fetch("id") }

    definition = RecordingStudioWebhooks::ProviderDefinition.new(
      "demo",
      signature_verifier: verifier,
      event_type_extractor: type_extractor,
      event_id_extractor: id_extractor
    )

    assert_equal verifier, definition.signature_verifier
    assert_equal type_extractor, definition.event_type
    assert_equal id_extractor, definition.event_id
  end

  def test_callback_dsl_setters_assign_callables_during_definition_build
    verifier = ->(_env, _raw, _headers) { true }
    type_extractor = ->(payload) { payload.fetch("event") }
    id_extractor = ->(payload) { payload.fetch("event_id") }

    definition = RecordingStudioWebhooks::ProviderDefinition.new("demo") do
      signature_verifier(verifier)
      event_type(type_extractor)
      event_id(id_extractor)
    end

    assert_equal verifier, definition.signature_verifier
    assert_equal type_extractor, definition.event_type
    assert_equal id_extractor, definition.event_id
  end
end
