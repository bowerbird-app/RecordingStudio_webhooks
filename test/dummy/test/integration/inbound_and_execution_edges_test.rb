# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"
require_relative "../support/webhook_admin_examples"

class InboundAndExecutionEdgesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include WebhookAdminExamples

  setup do
    setup_webhook_admin!
    sign_in @user
  end

  teardown { teardown_webhook_admin! }

  test "public intake maps rejected requests to a generic status" do
    token = @endpoint.issue_token!.plaintext_token

    post "/webhooks/inbound",
      params: "hello",
      headers: intake_headers(token).merge("CONTENT_TYPE" => "text/plain")
    assert_response :unsupported_media_type
    assert_equal "invalid", response.parsed_body.fetch("status")

    post "/webhooks/inbound",
      params: "{",
      headers: intake_headers(token)
    assert_response :bad_request
    assert_equal "invalid", response.parsed_body.fetch("status")

    post "/webhooks/inbound",
      params: JSON.generate(id: "evt_no_type"),
      headers: intake_headers(token)
    assert_response :unprocessable_entity

    post "/webhooks/inbound",
      params: JSON.generate(id: "x" * 256, type: "demo.received"),
      headers: intake_headers(token)
    assert_response :unprocessable_entity

    @endpoint = RecordingStudioWebhooks::EndpointLifecycle.update!(
      endpoint: @endpoint,
      attributes: { enabled: false },
      actor: @user
    )
    post "/webhooks/inbound",
      params: JSON.generate(id: "evt_disabled", type: "demo.received"),
      headers: intake_headers(token)
    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body.fetch("status")
  end

  test "intake accepts vendor json, honors hooks, and stores only safe provenance" do
    register_provider_once(
      "probe_signature",
      signature_verifier: ->(**_kwargs) { true },
      event_type_extractor: ->(payload:, context:) { context.payload["type"] || payload["type"] },
      event_id_extractor: ->(payload) { payload["id"] }
    )
    signed = create_webhook_endpoint!(label: "Signed probe", provider_name: "probe_signature")
    token = signed.issue_token!.plaintext_token

    post "/webhooks/inbound",
      params: JSON.generate(id: "evt_vendor", type: "demo.received"),
      headers: intake_headers(token).merge("CONTENT_TYPE" => "application/vnd.api+json", "HTTP_X_PROBE" => "ok")
    assert_response :accepted

    @webhooks_configuration.rate_limiter = ->(endpoint:, payload:) { endpoint.present? && payload.present? }
    post "/webhooks/inbound",
      params: JSON.generate(id: "evt_keyword_limit", type: "demo.received"),
      headers: intake_headers(@endpoint.issue_token!.plaintext_token)
    assert_response :accepted

    @webhooks_configuration.rate_limiter = ->(_endpoint, _context) { false }
    post "/webhooks/inbound",
      params: JSON.generate(id: "evt_limited", type: "demo.received"),
      headers: intake_headers(@endpoint.issue_token!.plaintext_token)
    assert_response :too_many_requests
    assert_equal "unavailable", response.parsed_body.fetch("status")

    denied = Object.new
    def denied.success? = false
    @webhooks_configuration.rate_limiter = nil
    @webhooks_configuration.authorization_hook = ->(_endpoint, _token, _context) { denied }
    post "/webhooks/inbound",
      params: JSON.generate(id: "evt_denied", type: "demo.received"),
      headers: intake_headers(@endpoint.issue_token!.plaintext_token)
    assert_response :forbidden
    assert_equal "unauthorized", response.parsed_body.fetch("status")

    @webhooks_configuration.authorization_hook = ->(_context) { raise "hook failed" }
    post "/webhooks/inbound",
      params: JSON.generate(id: "evt_hook_error", type: "demo.received"),
      headers: intake_headers(@endpoint.issue_token!.plaintext_token)
    assert_response :forbidden
  end

  test "intake keeps an explicit event id and falls back to a payload digest" do
    token = @endpoint.issue_token!(actor: @user).plaintext_token
    result = RecordingStudioWebhooks::InboundIntake.call(
      token: token,
      raw_payload: JSON.generate(type: "demo.received", name: "Ada"),
      content_type: "application/json",
      headers: { "X-Probe" => "ok", 1 => "skip", "bad" => Object.new },
      request_metadata: { request_id: 12, remote_ip: "127.0.0.1", extra: Object.new },
      provider_event_id: "explicit-id",
      actor: @user
    )

    assert_equal "accepted", result.code
    event = result.record
    assert_equal "explicit-id", event.provider_event_id
    assert_equal "12", event.provenance.fetch("request_id")
    refute event.provenance.key?("extra")

    previous_actor = RecordingStudio.configuration.actor
    RecordingStudio.configuration.actor = -> { raise "actor unavailable" }
    raised = RecordingStudioWebhooks::InboundIntake.call(
      token: token,
      raw_payload: JSON.generate(type: "demo.received"),
      content_type: "application/json",
      event_type: "demo.received"
    )
    assert_equal "accepted", raised.code
    assert_equal "payload:#{RecordingStudioWebhooks::CanonicalJson.digest({ "type" => "demo.received" })}",
      raised.record.deduplication_key
  ensure
    RecordingStudio.configuration.actor = previous_actor if defined?(previous_actor) && previous_actor
  end

  test "oversized bodies are rejected by the controller when they pass the guard" do
    token = @endpoint.issue_token!.plaintext_token
    @webhooks_configuration.max_payload_bytes = 40

    post "/webhooks/inbound",
      params: JSON.generate(id: "evt_big", type: "demo.received", note: "x" * 80),
      headers: intake_headers(token)

    assert_response :content_too_large
    assert_equal "invalid", response.parsed_body.fetch("status")

    direct = RecordingStudioWebhooks::InboundIntake.call(
      token: token,
      raw_payload: JSON.generate(id: "evt_direct_big", type: "demo.received", note: "x" * 80),
      content_type: "application/json",
      actor: @user
    )
    assert_equal 413, direct.status
    assert_equal "payload_too_large", direct.code
  end

  test "disabled actions are skipped and handlers run, retry, or fail" do
    register_action_once(
      "demo.disabled_action",
      ->(_context) { true },
      provider: "demo",
      event: "demo.disabled",
      policy: { enabled: false }
    )
    disabled = accept_event("evt_disabled_action", "demo.disabled")
    skipped = disabled.action_attempts.find_by!(action_name: "demo.disabled_action")
    assert_equal "skipped", skipped.status
    assert_equal "action_disabled", skipped.last_error

    calls = 0
    register_action_once(
      "demo.retry_action",
      ->(_context) {
        calls += 1
        raise "try again" if calls == 1

        true
      },
      provider: "demo",
      event: "demo.retry",
      policy: { max_retries: 1 }
    )
    retried = accept_event("evt_retry", "demo.retry").action_attempts.find_by!(action_name: "demo.retry_action")
    first = RecordingStudioWebhooks::ExecuteActionAttempt.call(retried.id)
    assert_equal "action_retry_scheduled", first.code
    assert_equal "queued", retried.reload.status
    assert_equal "action_execution_failed", retried.last_error

    second = RecordingStudioWebhooks::ExecuteActionAttempt.call(retried.id)
    assert_equal "action_succeeded", second.code

    register_action_once("demo.perform_action", PerformHandler, provider: "demo", event: "demo.perform")
    performed = accept_event("evt_perform", "demo.perform").action_attempts.find_by!(action_name: "demo.perform_action")
    assert_equal "action_succeeded", RecordingStudioWebhooks::ExecuteActionAttempt.call(performed.id).code

    register_action_once("demo.zero_arg_action", ZeroArgHandler, provider: "demo", event: "demo.zero")
    zero = accept_event("evt_zero", "demo.zero").action_attempts.find_by!(action_name: "demo.zero_arg_action")
    assert_equal "action_succeeded", RecordingStudioWebhooks::ExecuteActionAttempt.call(zero.id).code

    register_action_once("demo.broken_action", BrokenHandler, provider: "demo", event: "demo.broken", policy: { max_retries: 0 })
    broken = accept_event("evt_broken", "demo.broken").action_attempts.find_by!(action_name: "demo.broken_action")
    assert_equal "action_failed", RecordingStudioWebhooks::ExecuteActionAttempt.call(broken.id).code
    assert_equal "failed", broken.reload.status

    register_action_once("demo.empty_action", EmptyHandler, provider: "demo", event: "demo.empty", policy: { max_retries: 0 })
    empty = accept_event("evt_empty", "demo.empty").action_attempts.find_by!(action_name: "demo.empty_action")
    assert_equal "action_failed", RecordingStudioWebhooks::ExecuteActionAttempt.call(empty.id).code
  end

  test "a missing or replaced action is skipped and the next sequential action is dispatched" do
    missing = accept_event("evt_missing_action", "demo.received").action_attempts.first
    RecordingStudioWebhooks.configuration.actions.stub(:fetch, nil) do
      result = RecordingStudioWebhooks::ExecuteActionAttempt.call(missing.id)
      assert_equal "action_unavailable", result.code
    end
    assert_equal "skipped", missing.reload.status

    register_action_once(
      "demo.seq_one",
      ->(_context) { true },
      provider: "demo",
      event: "demo.sequence",
      priority: 1,
      policy: { execution_mode: "sequential", max_retries: 0 }
    )
    register_action_once(
      "demo.seq_two",
      ->(_context) { true },
      provider: "demo",
      event: "demo.sequence",
      priority: 2,
      policy: { execution_mode: "sequential", max_retries: 0 }
    )
    event = accept_event("evt_sequence", "demo.sequence")
    first, second = event.action_attempts.order(:execution_position).to_a
    assert_equal "action_succeeded", RecordingStudioWebhooks::ExecuteActionAttempt.call(first.id).code
    assert_equal "queued", second.reload.status
    assert_equal "action_attempt_not_dispatchable",
      RecordingStudioWebhooks::DispatchActionAttempt.call(first.id).code

    assert_equal "action_attempt_not_found",
      RecordingStudioWebhooks::ExecuteActionAttempt.call(SecureRandom.uuid).code
    assert_equal "action_attempt_not_found",
      RecordingStudioWebhooks::DispatchActionAttempt.call(SecureRandom.uuid).code
  end

  test "recovery requeues stale work and the doctor tasks report status" do
    event = accept_event("evt_recover", "demo.received")
    queued = event.action_attempts.first
    queued.queue_for_dispatch!
    running = accept_event("evt_running", "demo.received").action_attempts.first
    running.claim_execution!

    RecordingStudioWebhooks::RecoverActionAttempts.call(now: 20.minutes.from_now)
    assert_equal "retrying", queued.reload.status
    assert_equal "dispatch_unavailable", queued.last_error
    assert_equal "failed", running.reload.status
    assert_equal "action_execution_failed", running.last_error

    Rails.application.load_tasks
    stdout, = capture_io do
      Rake::Task["recording_studio_webhooks:status"].reenable
      Rake::Task["recording_studio_webhooks:status"].invoke
    end
    report = JSON.parse(stdout)
    assert_equal true, report.dig("tables", "endpoints")
    refute report.key?("token_digest_secret")

    stdout, = capture_io do
      Rake::Task["recording_studio_webhooks:doctor"].reenable
      Rake::Task["recording_studio_webhooks:doctor"].invoke
    end
    assert_includes stdout, "OK: admin authorization is configured"

    stdout, = capture_io do
      Rake::Task["recording_studio_webhooks:dispatch_due"].reenable
      Rake::Task["recording_studio_webhooks:dispatch_due"].invoke
    end
    assert_match(/Reconciled \d+ action attempt/, stdout)

    assert_raises(SystemExit) do
      RecordingStudioWebhooks::Endpoint.stub(:table_exists?, -> { raise ActiveRecord::ActiveRecordError, "down" }) do
        Rake::Task["recording_studio_webhooks:doctor"].reenable
        Rake::Task["recording_studio_webhooks:doctor"].invoke
      end
    end
  end

  test "dispatch adapters enqueue an attempt id without calling an external URL" do
    require "sidekiq"
    pushed = []
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    Sidekiq::Client.stub(:push, ->(payload) { pushed << payload }) do
      @webhooks_configuration.dispatcher = :sidekiq
      RecordingStudioWebhooks::Dispatcher.enqueue("attempt-now")
      RecordingStudioWebhooks::Dispatcher.enqueue("attempt-later", wait_until: Time.utc(2026, 1, 2, 3, 4, 5))
    end
    assert_equal ["attempt-now"], pushed.first.fetch("args")
    assert_equal "attempt-later", pushed.last.fetch("args").first
    assert_equal Time.utc(2026, 1, 2, 3, 4, 5).to_f, pushed.last.fetch("at")
    assert_equal false, pushed.first.fetch("retry")
    refute pushed.first.key?("at")

    @webhooks_configuration.dispatcher = :active_job
    assert_enqueued_with(job: RecordingStudioWebhooks::ExecuteActionAttemptActiveJob, args: ["attempt-job"]) do
      RecordingStudioWebhooks::Dispatcher.enqueue("attempt-job", wait_until: 1.hour.from_now)
    end

    positional = []
    single = []
    @webhooks_configuration.dispatcher = ->(attempt_id, wait_until) { positional << [attempt_id, wait_until] }
    RecordingStudioWebhooks::Dispatcher.enqueue("positional", wait_until: Time.utc(2026, 2, 2))
    @webhooks_configuration.dispatcher = ->(attempt_id) { single << attempt_id }
    RecordingStudioWebhooks::Dispatcher.enqueue("single")

    assert_equal [["positional", Time.utc(2026, 2, 2)]], positional
    assert_equal ["single"], single

    attempt = accept_event("evt_jobs", "demo.received").action_attempts.first
    assert_equal "action_succeeded", RecordingStudioWebhooks::ExecuteActionAttemptJob.new.perform(attempt.id).code
    other = accept_event("evt_active_job", "demo.received").action_attempts.first
    assert_equal "action_succeeded",
      RecordingStudioWebhooks::ExecuteActionAttemptActiveJob.perform_now(other.id).code
  ensure
    ActiveJob::Base.queue_adapter = previous_adapter if previous_adapter
  end

  private

  def intake_headers(token)
    {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer #{token}"
    }
  end

  def accept_event(event_id, event_type)
    token = @endpoint.issue_token!.plaintext_token
    result = RecordingStudioWebhooks::InboundIntake.call(
      token: token,
      raw_payload: JSON.generate(id: event_id, type: event_type),
      content_type: "application/json",
      actor: @user
    )
    assert_equal "accepted", result.code, result.code
    @endpoint.inbound_events.find_by!(provider_event_id: event_id)
  end

  class PerformHandler
    def initialize(context)
      @context = context
    end

    def perform(context)
      context.endpoint.present? && @context.present?
    end
  end

  class ZeroArgHandler
    def initialize; end

    def call(_context)
      true
    end
  end

  class BrokenHandler
    def initialize(_context); end
  end

  class EmptyHandler
    def initialize; end
  end
end
