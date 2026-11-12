# frozen_string_literal: true

RecordingStudioApi.configure do |config|
  config.openapi_title = "Webhook Demo API"
  config.documentation_enabled = false
  config.api_management_authorization_required = false
  config.rate_limit_oauth_enabled = false
  config.rate_limit_api_pre_auth_enabled = false
  config.rate_limit_api_enabled = false
  config.rate_limit_fail_closed = false
  config.api_request_logging_enabled = false
end
