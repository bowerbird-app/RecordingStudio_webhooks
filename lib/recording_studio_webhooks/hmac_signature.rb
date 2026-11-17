# frozen_string_literal: true

require "openssl"
require "active_support/security_utils"

module RecordingStudioWebhooks
  # HMAC-SHA256 over "#{timestamp}.#{raw_body}". The signing secret is read
  # from the endpoint. Header names are matched case-insensitively.
  class HmacSignature
    DEFAULT_SIGNATURE_HEADER = "x-recording-studio-signature"
    DEFAULT_TIMESTAMP_HEADER = "x-recording-studio-timestamp"
    DEFAULT_TOLERANCE = 300

    def self.from(value)
      return new if value == true
      raise ConfigurationError, "hmac options are invalid" unless value.is_a?(Hash)

      allowed = %i[signature_header timestamp_header tolerance]
      options = value.transform_keys(&:to_sym)
      raise ConfigurationError, "hmac options are invalid" unless (options.keys - allowed).empty?

      new(**options.compact)
    end

    def initialize(
      signature_header: DEFAULT_SIGNATURE_HEADER,
      timestamp_header: DEFAULT_TIMESTAMP_HEADER,
      tolerance: DEFAULT_TOLERANCE
    )
      @signature_header = normalize_header_name(signature_header)
      @timestamp_header = normalize_header_name(timestamp_header)
      @tolerance = tolerance_seconds(tolerance)
      raise ConfigurationError, "signature header is invalid" if @signature_header.empty?
      raise ConfigurationError, "timestamp header is invalid" if @timestamp_header.empty?

      freeze
    end

    def call(context)
      secret = secret_from(context)
      return false if secret.empty?

      headers = headers_from(context)
      timestamp = header_value(headers, @timestamp_header)
      signature = header_value(headers, @signature_header)
      return false unless timestamp && signature && fresh?(timestamp)

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body_from(context)}")
      signatures_match?(signature, expected)
    end

    def inspect
      "#<#{self.class.name} signature_header=#{@signature_header.inspect} " \
        "timestamp_header=#{@timestamp_header.inspect} tolerance=#{@tolerance}>"
    end

    private

    def secret_from(context)
      endpoint = context.respond_to?(:endpoint) ? context.endpoint : nil
      return "" unless endpoint.respond_to?(:signing_secret)

      endpoint.signing_secret.to_s
    end

    def headers_from(context)
      headers = context.respond_to?(:headers) ? context.headers : nil
      headers.respond_to?(:[]) ? headers : {}
    end

    def body_from(context)
      context.respond_to?(:raw_payload) ? context.raw_payload.to_s : ""
    end

    def header_value(headers, name)
      [name, name.tr("-", "_"), "http_#{name.tr('-', '_')}"].each do |key|
        value = headers[key] || (headers[key.to_sym] if headers.respond_to?(:[]))
        return value.to_s if value.is_a?(String) || value.is_a?(Numeric)
      end
      nil
    end

    def fresh?(timestamp)
      return false unless /\A\d+\z/.match?(timestamp.to_s)

      (Time.now.to_i - timestamp.to_i).abs <= @tolerance
    end

    def signatures_match?(provided, expected)
      return false unless provided.bytesize == expected.bytesize && expected.bytesize.positive?

      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end

    def normalize_header_name(value)
      value.to_s.downcase.strip.tr("_", "-").delete_prefix("http-")
    end

    def tolerance_seconds(value)
      seconds = Integer(value.respond_to?(:to_int) ? value.to_int : value)
      raise ConfigurationError, "timestamp tolerance must be positive" unless seconds.positive?

      seconds
    rescue ArgumentError, TypeError
      raise ConfigurationError, "timestamp tolerance must be a number of seconds"
    end
  end
end
