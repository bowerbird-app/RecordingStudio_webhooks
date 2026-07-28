# frozen_string_literal: true

# lib/recording_studio_webhooks/policy_resolver.rb
module RecordingStudioWebhooks
  # Resolves webhook policy through eight named precedence slots. The slots are
  # intentionally explicit so hosts can audit policy provenance:
  #
  # 1. framework_default    - engine baseline
  # 2. configuration_default - host-wide default override
  # 3. global               - host-wide operational override
  # 4. provider             - provider registration override
  # 5. provider_event       - matching provider event rule
  # 6. endpoint             - immutable endpoint snapshot override
  # 7. endpoint_event       - matching endpoint event rule
  # 8. action               - matching action override
  #
  # `execution_mode` deliberately ignores slot 8: it is resolved once when an
  # incoming log is accepted and copied to every action attempt for that log.
  class PolicyResolver
    SLOT_NAMES = %i[
      framework_default
      configuration_default
      global
      provider
      provider_event
      endpoint
      endpoint_event
      action
    ].freeze

    Slot = Data.define(:name, :override, :pattern)

    class Resolution
      attr_reader :policy, :source, :pattern, :execution_mode, :slots, :fingerprint

      def initialize(policy:, source:, pattern:, slots:)
        @policy = policy
        @source = source.to_s.freeze
        @pattern = pattern.to_s.freeze
        @execution_mode = policy.execution_mode.freeze
        @slots = ImmutableSnapshot.build(
          slots.map { |slot| { name: slot.name, pattern: slot.pattern, policy: slot.override } }
        )
        @fingerprint = CanonicalJson.digest(
          policy: policy.to_h,
          source: source,
          pattern: pattern,
          slots: @slots
        ).freeze
        freeze
      end

      def enabled? = policy.enabled?
      def sequential? = execution_mode == "sequential"
      def to_h
        ImmutableSnapshot.build(
          values: policy.to_h,
          source: source,
          pattern: pattern,
          execution_mode: execution_mode,
          fingerprint: fingerprint,
          slots: slots
        )
      end
    end

    class << self
      def resolve_event(configuration:, provider:, endpoint:, event_type:)
        slots = [
          Slot.new(:framework_default, configuration.framework_policy_overrides, "*"),
          Slot.new(:configuration_default, configuration.default_policy_overrides, "*"),
          Slot.new(:global, configuration.global_policy_overrides, "*"),
          Slot.new(:provider, provider.policy_overrides, "*"),
          event_slot(:provider_event, provider.event_policies, event_type),
          Slot.new(:endpoint, endpoint.policy_overrides || {}, "*"),
          event_slot(:endpoint_event, endpoint.event_policies || {}, event_type),
          Slot.new(:action, {}, "*")
        ]

        build_resolution(slots, required_redaction_keys: configuration.secret_redaction_keys)
      end

      # Applies action controls (enabled/retries/redaction) while retaining the
      # event-level execution mode and its source/pattern. This prevents a
      # single incoming log from running some actions independently and others
      # sequentially.
      def resolve_action(event_resolution:, action:, required_redaction_keys:)
        action_override = Policy.normalize_override(action.policy_overrides).except("execution_mode")
        slots = event_resolution.slots.map do |slot|
          Slot.new(slot.fetch("name").to_sym, slot.fetch("policy"), slot.fetch("pattern"))
        end
        slots[-1] = Slot.new(:action, action_override, action.event_pattern.value)

        values = merge_slots(slots, required_redaction_keys: required_redaction_keys)
        values["execution_mode"] = event_resolution.execution_mode
        Resolution.new(
          policy: Policy.new(values),
          source: event_resolution.source,
          pattern: event_resolution.pattern,
          slots: slots
        )
      end

      # Event-policy rules accept a Hash (`"invoice.*" => { max_retries: 1 }`)
      # or an Array of `{ pattern:, policy: }` hashes. Only exact, suffix
      # wildcard, and catch-all patterns are accepted.
      def normalize_event_policies(value)
        pairs =
          case value
          when nil then []
          when Hash then value.map { |pattern, policy| [pattern, policy] }
          when Array
            value.map do |entry|
              hash = entry.respond_to?(:to_h) ? entry.to_h : {}
              [hash[:pattern] || hash["pattern"], hash[:policy] || hash["policy"] || {}]
            end
          else
            raise InvalidPolicyError, "event policies must be a hash or array"
          end

        policies = pairs.map do |pattern, policy|
          event_pattern = EventPattern.new(pattern)
          {
            "pattern" => event_pattern.value,
            "policy" => Policy.normalize_override(policy || {})
          }
        end
        duplicate = policies.group_by { |entry| entry.fetch("pattern") }.find { |_pattern, rules| rules.size > 1 }
        raise InvalidPolicyError, "event policy pattern is duplicated" if duplicate

        ImmutableSnapshot.build(
          policies.sort_by do |entry|
            kind, length = EventPattern.new(entry.fetch("pattern")).specificity
            [-kind, -length, entry.fetch("pattern")]
          end
        )
      rescue InvalidEventPatternError => e
        raise InvalidPolicyError, e.message
      end

      def matching_event_policy(event_policies, event_type)
        rules = normalize_event_policies(event_policies)
        matching = rules.filter_map do |rule|
          pattern = EventPattern.new(rule.fetch("pattern"))
          [pattern, rule.fetch("policy")] if pattern.matches?(event_type)
        end
        return ["*", {}] if matching.empty?

        pattern, policy = matching.min_by do |candidate|
          kind, length = candidate.first.specificity
          [-kind, -length, candidate.first.value]
        end
        [pattern.value, policy]
      end

      private

      def event_slot(name, event_policies, event_type)
        pattern, override = matching_event_policy(event_policies, event_type)
        Slot.new(name, override, pattern)
      end

      def build_resolution(slots, required_redaction_keys:)
        values = merge_slots(slots, required_redaction_keys: required_redaction_keys)
        mode_slot = slots.reverse.find { |slot| slot.override.key?("execution_mode") } || slots.first
        Resolution.new(
          policy: Policy.new(values),
          source: mode_slot.name,
          pattern: mode_slot.pattern,
          slots: slots
        )
      end

      def merge_slots(slots, required_redaction_keys:)
        values = Policy::DEFAULT_VALUES.dup
        slots.each { |slot| values.merge!(Policy.normalize_override(slot.override)) }
        values["redaction_keys"] = (Array(required_redaction_keys) + Array(values["redaction_keys"]))
          .map { |key| key.to_s.downcase }
          .uniq
          .sort
        values
      end
    end
  end
end
