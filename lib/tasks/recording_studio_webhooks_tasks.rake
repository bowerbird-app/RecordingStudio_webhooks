# frozen_string_literal: true

namespace :recording_studio_webhooks do
  desc "Print a non-secret configuration and persistence status report"
  task status: :environment do
    tables = {
      endpoints: RecordingStudioWebhooks::Endpoint.table_exists?,
      endpoint_tokens: RecordingStudioWebhooks::EndpointToken.table_exists?,
      inbound_events: RecordingStudioWebhooks::InboundEvent.table_exists?,
      action_plans: RecordingStudioWebhooks::ActionPlan.table_exists?
    }

    report = RecordingStudioWebhooks.report.merge(
      "recording_studio_available" => defined?(::RecordingStudio::Recording).present?,
      "tables" => tables
    )
    puts JSON.pretty_generate(report)
  rescue ActiveRecord::ActiveRecordError, ActiveRecord::NoDatabaseError
    puts JSON.pretty_generate(RecordingStudioWebhooks.report.merge("database" => "unavailable"))
  end

  desc "Check that the inbound webhook engine is ready without exposing secrets"
  task doctor: :environment do
    checks = []
    tables = [
      RecordingStudioWebhooks::Endpoint,
      RecordingStudioWebhooks::EndpointToken,
      RecordingStudioWebhooks::InboundEvent,
      RecordingStudioWebhooks::ActionPlan
    ]

    checks << [ "RecordingStudio::Recording is loaded", defined?(::RecordingStudio::Recording).present? ]
    checks << [ "admin authorization is configured", RecordingStudioWebhooks.configuration.admin_authorizer.present? ]
    checks << [ "at least one provider is registered", RecordingStudioWebhooks.providers.any? ]
    checks << [ "all four UUID tables exist", tables.all?(&:table_exists?) ]
    checks << [
      "Sidekiq is available for the default dispatcher",
      RecordingStudioWebhooks.configuration.dispatcher != :sidekiq ||
        Gem::Specification.find_all_by_name("sidekiq").any?
    ]

    checks.each { |label, passing| puts "#{passing ? "OK" : "FAIL"}: #{label}" }
    abort "Recording Studio Webhooks doctor found configuration problems." unless checks.all?(&:last)
  rescue ActiveRecord::ActiveRecordError, ActiveRecord::NoDatabaseError
    abort "Recording Studio Webhooks doctor could not inspect the database."
  end

  desc "Reconcile pending, retryable, and stale queued action plans"
  task dispatch_due: :environment do
    results = RecordingStudioWebhooks::RecoverActionPlans.call
    puts "Reconciled #{results.count} action plan(s)."
  end
end
