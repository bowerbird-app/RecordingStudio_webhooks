# frozen_string_literal: true

module RecordingStudioWebhooks
  module Public
    # This controller intentionally uses the stateless API base instead of
    # weakening CSRF protection on the cookie-backed administrative controller.
    # Public intake authenticates with an endpoint credential header, never a
    # browser session.
    class IntakeController < ActionController::API

      def create
        raw_payload = bounded_raw_payload
        return render_invalid_payload if raw_payload.nil?

        result = InboundIntake.call(
          provider_name: route_value(:provider),
          endpoint_recording_id: route_value(:endpoint_recording_id),
          token: bearer_token,
          raw_payload: raw_payload,
          content_type: request.content_type,
          headers: signature_headers,
          request_metadata: request_provenance
        )

        render json: { status: public_status(result) }, status: result.status
      rescue ActionController::BadRequest
        render json: { status: "invalid" }, status: :bad_request
      end

      private

      def webhook_configuration
        RecordingStudioWebhooks.configuration
      end

      # Rack's bounded read also protects chunked requests, which have no
      # trustworthy Content-Length. Do not use `raw_post`: it buffers the
      # complete request before the size check can run.
      def bounded_raw_payload
        input = request.get_header("rack.input") || request.body
        body = input.read(webhook_configuration.max_payload_bytes + 1)
        return nil if body.nil? || body.bytesize > webhook_configuration.max_payload_bytes

        body
      rescue IOError, SystemCallError
        nil
      end

      def render_invalid_payload
        render json: { status: "invalid" }, status: :payload_too_large
      end

      def route_value(key)
        request.path_parameters[key] || request.path_parameters[key.to_s]
      end

      def bearer_token
        authorization = request.get_header("HTTP_AUTHORIZATION").to_s
        bearer = authorization.match(/\ABearer ([^\s]+)\z/i)
        return bearer[1] if bearer

        request.get_header("HTTP_X_RECORDING_STUDIO_WEBHOOK_TOKEN").presence
      end

      # These headers exist only while a configured verifier is running. They
      # are never included in provenance or persisted with an inbound event.
      def signature_headers
        request.headers.each.each_with_object({}) do |(key, value), result|
          next unless key.start_with?("HTTP_") || %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
          next if %w[HTTP_AUTHORIZATION HTTP_X_RECORDING_STUDIO_WEBHOOK_TOKEN].include?(key)

          result[key] = value.to_s.byteslice(0, 4_096)
        end
      end

      def request_provenance
        {
          request_id: request.request_id,
          remote_ip: request.remote_ip,
          user_agent: request.user_agent,
          content_type: request.content_type
        }
      end

      def public_status(result)
        return "accepted" if result.code == "accepted"
        return "duplicate" if result.code == "duplicate"
        return "unauthorized" if result.status.in?([401, 403])
        return "not_found" if result.status == 404
        return "invalid" if result.status.in?([400, 413, 415, 422])

        "unavailable"
      end
    end
  end
end
