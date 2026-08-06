# frozen_string_literal: true

# lib/recording_studio_webhooks/configuration.rb
module RecordingStudioWebhooks
  class Configuration
    DEFAULT_REDACTION_KEYS = %w[
      authorization api_key password secret signature token webhook_secret
    ].freeze
    DEFAULT_CONTENT_TYPES = %w[application/json application/*+json].freeze
    DEFAULT_PROVENANCE_KEYS = %w[
      request_id remote_ip user_agent content_type provider_event_id
    ].freeze

    attr_reader :providers, :actions, :default_policy, :queue_name, :dispatcher,
      :max_payload_bytes, :content_types, :secret_redaction_keys, :provenance_keys,
      :authorization_hook, :rate_limiter, :admin_authorizer, :admin_recording_scope,
      :provider_roots, :action_roots, :framework_policy_overrides,
      :default_policy_overrides, :global_policy_overrides, :endpoint_token_bytesize
    attr_reader :automatic_discovery

    def initialize
      @providers = Registry.new(ProviderDefinition)
      @actions = Registry.new(ActionDefinition)
      @framework_policy_overrides = {}
      @default_policy_overrides = {}
      @global_policy_overrides = {}
      @default_policy = Policy.default
      @queue_name = "recording_studio_webhooks"
      @dispatcher = :sidekiq
      @max_payload_bytes = 1_048_576
      @endpoint_token_bytesize = 18
      @content_types = DEFAULT_CONTENT_TYPES
      @secret_redaction_keys = DEFAULT_REDACTION_KEYS
      @provenance_keys = DEFAULT_PROVENANCE_KEYS
      @authorization_hook = nil
      @rate_limiter = nil
      @admin_authorizer = nil
      @admin_recording_scope = nil
      @token_digest_secret = nil
      @provider_roots = [].freeze
      @action_roots = [].freeze
      @automatic_discovery = false
    end

    def default_policy=(value)
      @default_policy_overrides = ImmutableSnapshot.build(Policy.normalize_override(value))
      @default_policy = Policy.new(Policy::DEFAULT_VALUES.merge(@default_policy_overrides))
    end

    # The first three PolicyResolver slots are host configurable here. The
    # remaining slots live with their natural owners: provider registrations,
    # immutable endpoint snapshots and event rules, and action registrations.
    def framework_policy=(value)
      @framework_policy_overrides = ImmutableSnapshot.build(Policy.normalize_override(value))
    end

    def global_policy=(value)
      @global_policy_overrides = ImmutableSnapshot.build(Policy.normalize_override(value))
    end

    def framework_policy = Policy.new(Policy::DEFAULT_VALUES.merge(framework_policy_overrides))

    def global_policy
      Policy.new(
        Policy::DEFAULT_VALUES
          .merge(framework_policy_overrides)
          .merge(default_policy_overrides)
          .merge(global_policy_overrides)
      )
    end

    def queue_name=(value)
      queue = value.to_s
      raise ConfigurationError, "queue name is invalid" unless /\A[a-zA-Z0-9_.:-]+\z/.match?(queue)

      @queue_name = queue.freeze
    end

    # Accepts :sidekiq, :active_job, or a callable receiving an action-attempt UUID.
    def dispatcher=(value)
      unless %i[sidekiq active_job].include?(value) || value.respond_to?(:call)
        raise ConfigurationError, "dispatcher must be :sidekiq, :active_job, or callable"
      end

      @dispatcher = value
    end

    def max_payload_bytes=(value)
      @max_payload_bytes = positive_integer(value, "max payload bytes")
    end

    def content_types=(value)
      values = Array(value).map { |item| item.to_s.downcase.strip }.reject(&:empty?).uniq.sort
      raise ConfigurationError, "content types are required" if values.empty?

      @content_types = values.map(&:freeze).freeze
    end

    def endpoint_token_bytesize=(value)
      bytesize = positive_integer(value, "endpoint token bytesize")
      raise ConfigurationError, "endpoint token bytesize must be at least 12" if bytesize < 12

      @endpoint_token_bytesize = bytesize
    end

    def secret_redaction_keys=(value)
      @secret_redaction_keys = normalized_keys(value, "secret redaction keys")
    end

    def provenance_keys=(value)
      keys = normalized_keys(value, "provenance keys")
      raise ConfigurationError, "provenance keys cannot contain secrets" if keys.any? { |key| Redactor.secret_key?(key) }

      @provenance_keys = keys
    end

    def authorization_hook=(value)
      @authorization_hook = callable_or_nil(value, "authorization hook")
    end

    def rate_limiter=(value)
      @rate_limiter = callable_or_nil(value, "rate limiter")
    end

    # Administrative access is deliberately opt-in. The engine's controllers
    # fail closed when this is unset, rather than guessing how a host app
    # represents an administrator.
    def admin_authorizer=(value)
      @admin_authorizer = callable_or_nil(value, "admin authorizer")
    end

    # An optional callable returning the RecordingStudio::Recording relation
    # visible to an already-authorized administrator. Returning nil means no
    # recordings are visible; it must never widen a host application's scope.
    def admin_recording_scope=(value)
      @admin_recording_scope = callable_or_nil(value, "admin recording scope")
    end

    # Kept out of #report and every persisted snapshot. Set this from credentials
    # or an initializer; rotating it invalidates existing endpoint tokens.
    def token_digest_secret=(value)
      @token_digest_secret = value.nil? ? nil : value.to_s.dup.freeze
    end

    def token_digest_secret_configured? = !@token_digest_secret.nil?

    # Keeps the HMAC key private while providing the only supported way to
    # calculate a token digest.
    def digest_token(value)
      if @token_digest_secret.nil? || @token_digest_secret.empty?
        OpenSSL::Digest::SHA256.hexdigest(value)
      else
        OpenSSL::HMAC.hexdigest("SHA256", @token_digest_secret, value)
      end
    end

    def provider_roots=(value)
      @provider_roots = discovery_roots(value)
    end

    def action_roots=(value)
      @action_roots = discovery_roots(value)
    end

    def automatic_discovery=(value)
      unless value == true || value == false
        raise ConfigurationError, "automatic discovery must be boolean"
      end

      @automatic_discovery = value
    end

    def provider(name, implementation = nil, **options, &)
      providers.register(name, implementation, **options, &)
    end

    def action(name, implementation = nil, **options, &)
      actions.register(name, implementation, **options, &)
    end

    alias register_provider provider
    alias register_action action

    def merge!(values)
      return self unless values.respond_to?(:each_pair) || values.respond_to?(:each)

      enumerable = values.respond_to?(:each_pair) ? values.each_pair : values.each
      enumerable.each do |key, value|
        setter = "#{key}="
        public_send(setter, value) if respond_to?(setter)
      end
      self
    end

    # Requires explicit absolute files from configured roots in lexical order.
    # It intentionally never asks Rails/Zeitwerk to infer a constant from a path.
    def discover!
      return [].freeze unless automatic_discovery

      files = (provider_roots + action_roots).flat_map { |root| ruby_files_under(root) }.uniq.sort
      files.each { |file| require file }
      files.freeze
    end

    def report
      ImmutableSnapshot.build(
        version: VERSION,
        queue_name: queue_name,
        dispatcher: dispatcher_name,
        max_payload_bytes: max_payload_bytes,
        content_types: content_types,
        secret_redaction_keys: secret_redaction_keys,
        provenance_keys: provenance_keys,
        admin_authorizer_configured: !admin_authorizer.nil?,
        admin_recording_scope_configured: !admin_recording_scope.nil?,
        policy_slots: {
          framework_default: framework_policy_overrides,
          configuration_default: default_policy_overrides,
          global: global_policy_overrides,
          provider: "provider registration policy",
          provider_event: "provider event policy",
          action: "action registration policy",
          endpoint: "endpoint snapshot policy"
        },
        default_policy: default_policy.to_h,
        providers: providers.all.map(&:snapshot),
        actions: actions.all.map(&:snapshot),
        automatic_discovery: automatic_discovery
      )
    end
    alias to_h report

    def inspect = "#<#{self.class.name} dispatcher=#{dispatcher_name.inspect} secrets=[FILTERED]>"

    private

    def positive_integer(value, label)
      integer = Integer(value)
      raise ConfigurationError, "#{label} must be positive" unless integer.positive?

      integer
    rescue ArgumentError, TypeError
      raise ConfigurationError, "#{label} must be an integer"
    end

    def normalized_keys(value, label)
      keys = Array(value).map { |item| item.to_s.downcase.strip }.reject(&:empty?).uniq.sort
      raise ConfigurationError, "#{label} are required" if keys.empty?

      keys.map(&:freeze).freeze
    end

    def callable_or_nil(value, label)
      return nil if value.nil?
      raise ConfigurationError, "#{label} must respond to call" unless value.respond_to?(:call)

      value
    end

    def discovery_roots(value)
      Array(value).map do |root|
        path = File.realpath(root.to_s)
        raise ConfigurationError, "discovery root must be a directory" unless File.directory?(path)

        path.freeze
      rescue Errno::ENOENT
        raise ConfigurationError, "discovery root is unavailable"
      end.uniq.sort.freeze
    end

    def ruby_files_under(root)
      prefix = "#{root}/"
      Dir.glob(File.join(root, "**", "*.rb")).sort.filter_map do |file|
        expanded = File.realpath(file)
        expanded if expanded.start_with?(prefix)
      rescue Errno::ENOENT
        nil
      end
    end

    def dispatcher_name
      dispatcher.is_a?(Symbol) ? dispatcher.to_s : "custom"
    end
  end
end
