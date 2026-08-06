# frozen_string_literal: true

# lib/recording_studio_webhooks/recording_studio_gateway.rb
module RecordingStudioWebhooks
  # Small adapter around Recording Studio's public API. Keeping the dependency
  # here prevents webhook intake from reaching into Recording Studio internals
  # and lets callers fail closed when the companion engine is unavailable.
  module RecordingStudioGateway
    module_function

    def available?
      defined?(::RecordingStudio) &&
        defined?(::RecordingStudio::Recording) &&
        ::RecordingStudio.respond_to?(:root_recording?) &&
        ::RecordingStudio::Recording.instance_methods.include?(:record) &&
        ::RecordingStudio::Recording.instance_methods.include?(:revise) &&
        ::RecordingStudio::Recording.instance_methods.include?(:log_event!)
    end

    def ensure_available!
      raise RecordingStudioUnavailableError, "Recording Studio is unavailable" unless available?
    end

    def root_recording!(recording)
      ensure_available!
      raise RecordingStudioConfigurationError, "a root recording is required" unless recording
      raise RecordingStudioConfigurationError, "recording must be a selected root" unless ::RecordingStudio.root_recording?(recording)

      recording
    rescue RecordingStudioUnavailableError, RecordingStudioConfigurationError
      raise
    rescue StandardError
      raise RecordingStudioConfigurationError, "recording is not a usable root"
    end

    def record!(root_recording:, recordable_class:, parent_recording:, actor: nil, metadata: {}, &)
      root = root_recording!(root_recording)
      root.record(
        recordable_class,
        actor: actor,
        metadata: safe_metadata(metadata),
        parent_recording: parent_recording,
        &
      )
    end

    # Recording Studio duplicates the current recordable and saves that new
    # instance before repointing the stable recording. The block must only
    # assign the new snapshot's attributes.
    def revise!(root_recording:, stable_recording:, actor: nil, metadata: {}, &)
      root = root_recording!(root_recording)
      root.revise(stable_recording, actor: actor, metadata: safe_metadata(metadata), &)
    end

    def log_event!(root_recording:, recording:, action:, actor: nil, metadata: {}, idempotency_key: nil)
      root = root_recording!(root_recording)
      ::RecordingStudio.assert_recording_belongs_to_root!(root, recording)
      recording.log_event!(
        action: action,
        actor: actor,
        metadata: safe_metadata(metadata),
        idempotency_key: idempotency_key
      )
    end

    def stable_recording_for(recordable)
      ensure_available!
      ::RecordingStudio::Recording.unscoped.find_by(
        recordable_type: recordable.class.name,
        recordable_id: recordable.id
      )
    end

    def safe_metadata(value)
      hash = value.respond_to?(:to_h) ? value.to_h : {}
      raise UnsafeMetadataError, "event metadata must be a hash" unless hash.is_a?(Hash)

      scrub_metadata(hash)
    end

    def scrub_metadata(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), result|
          next if Redactor.secret_key?(key)

          result[key.to_s] = scrub_metadata(item)
        end
      when Array
        value.map { |item| scrub_metadata(item) }
      when String
        Redactor.secret_location?(value) ? Redactor::FILTERED : value.byteslice(0, 512)
      when Numeric, TrueClass, FalseClass, NilClass
        value
      else
        value.to_s.byteslice(0, 512)
      end
    end
    private_class_method :scrub_metadata
  end
end
