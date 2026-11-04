# frozen_string_literal: true

require "cgi"
require "uri"

module RecordingStudioWebhooks
  module SafeReturnPath
    def self.call(value)
      path = value.to_s.strip
      return nil unless candidate_path?(path)

      uri = parse_relative_uri(path)
      return nil unless uri
      return nil unless safe_decoded_path?(uri.path.to_s)

      path
    end

    def self.candidate_path?(path)
      return false if path.empty? || path.start_with?("//") || !path.start_with?("/")
      return false if path.include?("\\") || path.match?(/[[:space:]]/)

      path.match?(%r{\A/[A-Za-z0-9._~!$&'()*+,;=:@%/?-]*\z})
    end
    private_class_method :candidate_path?

    def self.parse_relative_uri(path)
      uri = URI.parse(path)
      return unless uri.relative?
      return if uri.host.present? || uri.scheme.present?

      uri
    rescue URI::InvalidURIError
      nil
    end
    private_class_method :parse_relative_uri

    def self.safe_decoded_path?(path)
      decoded = CGI.unescape(path)
      !decoded.start_with?("//") && !decoded.include?("\\") && !decoded.include?("://")
    end
    private_class_method :safe_decoded_path?
  end
end
