# frozen_string_literal: true

module WebhookAdminExamples
  def setup_webhook_admin!
    @webhooks_configuration = RecordingStudioWebhooks.configuration
    @original_admin_authorizer = @webhooks_configuration.admin_authorizer
    @original_admin_recording_scope = @webhooks_configuration.admin_recording_scope
    @original_dispatcher = @webhooks_configuration.dispatcher
    @original_max_payload_bytes = @webhooks_configuration.max_payload_bytes
    @original_rate_limiter = @webhooks_configuration.rate_limiter
    @original_authorization_hook = @webhooks_configuration.authorization_hook

    @webhooks_configuration.admin_authorizer = ->(context) { context.actor&.email == "admin@admin.com" }
    @webhooks_configuration.admin_recording_scope = ->(_context) { RecordingStudio::Recording.where(trashed_at: nil) }

    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
    workspace = Workspace.create!(name: "Coverage #{SecureRandom.hex(4)}")
    @recording = RecordingStudio.root_recording_for(workspace)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @user)
    raise result.error if result.failure?

    @endpoint = create_webhook_endpoint!(label: "Coverage endpoint", provider_name: "demo")
    Current.actor = @user
  end

  def teardown_webhook_admin!
    Current.actor = nil
    return unless @webhooks_configuration

    @webhooks_configuration.admin_authorizer = @original_admin_authorizer
    @webhooks_configuration.admin_recording_scope = @original_admin_recording_scope
    @webhooks_configuration.dispatcher = @original_dispatcher
    @webhooks_configuration.max_payload_bytes = @original_max_payload_bytes
    @webhooks_configuration.rate_limiter = @original_rate_limiter
    @webhooks_configuration.authorization_hook = @original_authorization_hook
  end

  def create_webhook_endpoint!(label:, provider_name:, identity: { "test" => true })
    RecordingStudioWebhooks::EndpointLifecycle.create!(
      endpoint: RecordingStudioWebhooks::Endpoint.new(
        recording_studio_recording_id: @recording.id,
        label: label,
        provider_name: provider_name,
        identity: identity,
        metadata: {},
        policy_overrides: {}
      ),
      actor: @user
    )
  end

  def register_provider_once(name, **)
    return if RecordingStudioWebhooks.configuration.providers.fetch(name)

    RecordingStudioWebhooks.register_provider(name, **)
  end

  def register_action_once(name, implementation = nil, **)
    return if RecordingStudioWebhooks.configuration.actions.fetch(name)

    RecordingStudioWebhooks.register_action(name, implementation, **)
  end

  def sandbox_path
    "/admin/webhooks/webhook_sandbox"
  end

  def post_sandbox(fields)
    post sandbox_path, params: { sandbox: fields }
  end
end
