# frozen_string_literal: true

class DummyWebhookTesterController < ApplicationController
  before_action :load_endpoints

  def show
    initialize_form_defaults
  end

  def create
    initialize_form_defaults

    token = extract_token(@endpoint_input, @headers_json)
    raise ArgumentError, "missing token" if token.blank?

    payload_hash = JSON.parse(@payload_json)
    headers = parse_headers_json(@headers_json)

    intake_result = RecordingStudioWebhooks::InboundIntake.call(
      token: token,
      raw_payload: @payload_json,
      content_type: "application/json",
      headers: headers,
      request_metadata: {
        remote_ip: request.remote_ip,
        user_agent: request.user_agent
      }
    )

    action_results = []
    if intake_result.code == "accepted" && intake_result.record.present?
      intake_result.record.action_attempts.order(:execution_position).each do |attempt|
        action_results << RecordingStudioWebhooks::ExecuteActionAttempt.call(attempt.id)
      end
    end

    @result = {
      status: intake_result.status,
      code: intake_result.code,
      event_id: intake_result.record&.id,
      provider_event_id: payload_hash["id"],
      attempts: action_results.map { |result| { code: result.code, status: result.status } }
    }
    render :show
  rescue JSON::ParserError
    @result = { status: 422, code: "json_invalid" }
    @form_error = "Payload and headers must be valid JSON objects."
    render :show, status: :unprocessable_entity
  rescue ArgumentError
    @result = { status: 422, code: "token_missing" }
    @form_error = "Provide a full inbound URL or token, and valid JSON payload."
    render :show, status: :unprocessable_entity
  end

  private

  def load_endpoints
    @endpoints = RecordingStudioWebhooks::Endpoint.current.includes(:endpoint_tokens).order(:provider_name, :label)
  end

  def initialize_form_defaults
    @endpoint_input = params.dig(:tester, :endpoint_input).to_s
    @headers_json = params.dig(:tester, :headers_json).to_s.presence || JSON.pretty_generate(default_headers_json)
    @payload_json = params.dig(:tester, :payload_json).to_s.presence || JSON.pretty_generate(default_payload_json)
  end

  def default_headers_json
    {
      "content-type" => "application/json",
      "x-webhook-timestamp" => Time.current.iso8601
    }
  end

  def default_payload_json
    {
      "id" => "evt_sample_123",
      "type" => "page.created",
      "data" => {
        "object" => {
          "id" => "obj_123",
          "status" => "active",
          "title" => "test page"
        }
      }
    }
  end

  def parse_headers_json(text)
    parsed = JSON.parse(text)
    raise JSON::ParserError unless parsed.is_a?(Hash)

    parsed.transform_keys { |key| key.to_s.downcase }
  end

  def extract_token(endpoint_input, headers_json)
    value = endpoint_input.to_s.strip
    return value if value.start_with?("rswh_")

    token_from_url(value) || token_from_headers(headers_json)
  end

  def token_from_url(value)
    return nil if value.blank?

    if value.include?("/webhooks/inbound/")
      match = value.match(%r{/webhooks/inbound/(rswh_[A-Za-z0-9_\-]+)})
      return match[1] if match
    end

    nil
  end

  def token_from_headers(headers_json)
    headers = parse_headers_json(headers_json)
    bearer = headers.fetch("authorization", "").to_s
    return nil if bearer.blank?

    bearer.split(" ", 2).last.to_s.presence
  rescue JSON::ParserError
    nil
  end
end