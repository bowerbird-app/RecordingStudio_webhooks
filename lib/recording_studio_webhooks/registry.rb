# frozen_string_literal: true

# lib/recording_studio_webhooks/registry.rb
module RecordingStudioWebhooks
  class Registry
    include Enumerable

    def initialize(definition_class)
      @definition_class = definition_class
      @entries = {}
      @insertion_order = []
      @mutex = Mutex.new
    end

    def register(name, implementation = nil, **options, &block)
      definition = @definition_class.new(name, implementation, **options, &block)

      @mutex.synchronize do
        raise DuplicateRegistrationError, "registration already exists" if @entries.key?(definition.name)

        @entries[definition.name] = definition
        @insertion_order << definition.name
      end
      definition
    end

    def fetch(name)
      @mutex.synchronize { @entries[name.to_s.downcase] }
    end

    def fetch!(name)
      fetch(name) || raise(ConfigurationError, "registration is unavailable")
    end

    # Lexical iteration is stable between processes, unlike constant discovery.
    def each(&block)
      all.each(&block)
    end

    def all
      @mutex.synchronize { @entries.values.sort_by(&:name).freeze }
    end

    # Exposed when registration order is itself intentional (for diagnostics).
    def insertion_order
      @mutex.synchronize { @insertion_order.dup.freeze }
    end

    def clear!
      @mutex.synchronize do
        @entries.clear
        @insertion_order.clear
      end
    end

    def matching(provider_name, event_name)
      all.select { |definition| definition.matches?(provider_name, event_name) }.sort_by(&:sort_key).freeze
    end

    def best_match(provider_name, event_name)
      matching(provider_name, event_name).first
    end
  end
end
