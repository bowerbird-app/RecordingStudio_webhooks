# frozen_string_literal: true

# lib/recording_studio_webhooks/dispatcher.rb
module RecordingStudioWebhooks
  module Dispatcher
    module_function

    def enqueue(attempt_id, wait_until: nil)
      adapter.enqueue(attempt_id.to_s, wait_until: wait_until)
    end

    def adapter
      case RecordingStudioWebhooks.configuration.dispatcher
      when :sidekiq then DirectSidekiqDispatcher.new
      when :active_job then ActiveJobDispatcher.new
      else CallableDispatcher.new(RecordingStudioWebhooks.configuration.dispatcher)
      end
    end

    class DirectSidekiqDispatcher
      def enqueue(attempt_id, wait_until: nil)
        require "sidekiq"

        payload = {
          "class" => "RecordingStudioWebhooks::ExecuteWebhookActionAttemptJob",
          "args" => [attempt_id],
          "queue" => RecordingStudioWebhooks.configuration.queue_name,
          "retry" => false
        }
        wait_until ? ::Sidekiq::Client.push_at(wait_until.to_f, payload) : ::Sidekiq::Client.push(payload)
      end
    end

    class ActiveJobDispatcher
      def enqueue(attempt_id, wait_until: nil)
        options = { queue: RecordingStudioWebhooks.configuration.queue_name }
        options[:wait_until] = wait_until if wait_until
        job = RecordingStudioWebhooks::ExecuteWebhookActionAttemptActiveJob.set(**options)
        job.perform_later(attempt_id)
      end
    end

    class CallableDispatcher
      def initialize(callable)
        @callable = callable
      end

      def enqueue(attempt_id, wait_until: nil)
        parameters = @callable.respond_to?(:parameters) ? @callable.parameters : []
        keywords = parameters.select { |kind, _| %i[key keyreq keyrest].include?(kind) }

        if keywords.any?
          @callable.call(attempt_id, wait_until: wait_until)
        elsif @callable.respond_to?(:arity) && @callable.arity == 1
          @callable.call(attempt_id)
        else
          @callable.call(attempt_id, wait_until)
        end
      end
    end
  end
end
