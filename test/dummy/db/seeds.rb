# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

find_or_record_child = lambda do |recordable, root_recording, parent_recording|
  RecordingStudio::Recording.find_by(
    root_recording: root_recording,
    parent_recording: parent_recording,
    recordable: recordable,
    trashed_at: nil
  ) || RecordingStudio.record!(
    action: "created",
    recordable: recordable,
    root_recording: root_recording,
    parent_recording: parent_recording
  ).recording
end

grant_admin_access = lambda do |recording, actor|
  next if RecordingStudioAccessible.role_for(actor: actor, recording: recording) == :admin

  result = RecordingStudioAccessible.grant_access(
    recording: recording,
    actor: actor,
    role: :admin,
    manager_actor: actor
  )

  raise "Failed to grant access: #{result.error}" if result.failure?
end

find_current_endpoint = lambda do |root_recording, provider_name, label|
  RecordingStudioWebhooks::Endpoint.current
    .joins(:recording_studio_recording)
    .where(
      provider_name: provider_name,
      label: label,
      recording_studio_recordings: { root_recording_id: root_recording.id }
    )
    .order(created_at: :desc)
    .first
end

ensure_endpoint = lambda do |root_recording, provider_name:, label:, identity:, metadata:, actor:|
  existing = find_current_endpoint.call(root_recording, provider_name, label)
  next existing if existing

  RecordingStudioWebhooks::EndpointLifecycle.create!(
    endpoint: RecordingStudioWebhooks::Endpoint.new(
      recording_studio_recording_id: root_recording.id,
      provider_name: provider_name,
      label: label,
      identity: identity,
      metadata: metadata,
      enabled: true
    ),
    actor: actor
  )
end

ensure_active_token = lambda do |endpoint, actor|
  current_token = endpoint.endpoint_tokens.current.order(active_at: :desc).first
  return current_token.token if current_token&.token.present?

  issuance = endpoint.issue_token!(actor: actor)
  issuance.plaintext_token
end

seed_inbound_event = lambda do |endpoint:, token:, event_id:, event_type:, payload:, request_id:, received_at: nil|
  existing = RecordingStudioWebhooks::InboundEvent.find_by(endpoint_id: endpoint.id, provider_event_id: event_id)
  if existing
    if received_at
      RecordingStudioWebhooks::InboundEvent.where(id: existing.id).update_all(
        received_at: received_at,
        updated_at: Time.current
      )
      existing.reload
    end
    next existing
  end

  result = RecordingStudioWebhooks::InboundIntake.call(
    token: token,
    raw_payload: payload.to_json,
    content_type: "application/json",
    headers: { "content-type" => "application/json" },
    request_metadata: {
      "request_id" => request_id,
      "ip_address" => "127.0.0.1",
      "user_agent" => "db:seed"
    },
    event_type: event_type,
    provider_event_id: event_id
  )

  unless %w[accepted duplicate].include?(result.code)
    raise "Failed to seed inbound event #{event_id}: #{result.code}"
  end

  event = result.record
  if received_at && event
    RecordingStudioWebhooks::InboundEvent.where(id: event.id).update_all(
      received_at: received_at,
      updated_at: Time.current
    )
    event.reload
  end

  event
end

# Create the admin user
user = User.find_or_create_by!(email: "admin@admin.com") do |u|
  u.password = "Password"
  u.password_confirmation = "Password"
end

# Create the workspace recordables
workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
accessible_workspace = Workspace.find_or_create_by!(name: "Client Workspace")
private_workspace = Workspace.find_or_create_by!(name: "Private Workspace")
folder = Folder.find_or_create_by!(name: "Product Docs")
page = Page.find_or_create_by!(title: "Getting Started")

previous_actor = Current.actor
Current.actor = user
previous_access_authorizer = RecordingStudioAccessible.configuration.access_management_authorizer
RecordingStudioAccessible.configuration.access_management_authorizer = ->(recording:, **) { recording.present? }

begin
  # Create the root recording
  root_recording = RecordingStudio.root_recording_for(workspace)
  accessible_root_recording = RecordingStudio.root_recording_for(accessible_workspace)
  private_root_recording = RecordingStudio.root_recording_for(private_workspace)

  folder_recording = find_or_record_child.call(folder, root_recording, root_recording)

  find_or_record_child.call(page, root_recording, folder_recording)

  [root_recording, accessible_root_recording, private_root_recording].each do |recording|
    grant_admin_access.call(recording, user)
  end

  seeded_endpoints = []
  if RecordingStudioWebhooks::Endpoint.table_exists?
    seeded_endpoints << ensure_endpoint.call(
      root_recording,
      provider_name: "demo",
      label: "Demo endpoint A",
      identity: { "environment" => "dummy", "channel" => "a" },
      metadata: { "owner" => "demo", "tier" => "sandbox" },
      actor: user
    )

    seeded_endpoints << ensure_endpoint.call(
      root_recording,
      provider_name: "demo",
      label: "Demo endpoint B",
      identity: { "environment" => "dummy", "channel" => "b" },
      metadata: { "owner" => "demo", "tier" => "staging" },
      actor: user
    )

    seeded_endpoints << ensure_endpoint.call(
      root_recording,
      provider_name: "stripe",
      label: "Stripe endpoint",
      identity: { "environment" => "dummy", "region" => "us" },
      metadata: { "owner" => "billing", "tier" => "sandbox" },
      actor: user
    )

    endpoint_tokens = seeded_endpoints.to_h do |endpoint|
      [endpoint, ensure_active_token.call(endpoint, user)]
    end

    events_to_seed = 200
    month_start = Time.current.beginning_of_month
    month_end = [Time.current.end_of_day, Time.current.end_of_month.end_of_day].min
    month_span_seconds = [(month_end - month_start).to_i, 1].max

    demo_event_types = %w[demo.received demo.created demo.updated].freeze
    stripe_event_types = %w[invoice.paid charge.succeeded customer.subscription.updated].freeze

    events_to_seed.times do |index|
      endpoint = seeded_endpoints[index % seeded_endpoints.length]
      endpoint_slot = (index % seeded_endpoints.length) + 1
      spread_ratio = events_to_seed == 1 ? 0.0 : index.to_f / (events_to_seed - 1)
      received_at = month_start + (month_span_seconds * spread_ratio).seconds

      if endpoint.provider_name == "stripe"
        event_type = stripe_event_types[index % stripe_event_types.length]
        payload = {
          id: format("seed_monthly_%03d_e%d", index + 1, endpoint_slot),
          type: event_type,
          data: {
            object: {
              customer: format("cus_seed_%03d", index + 1),
              amount_paid: ((index % 25) + 1) * 100
            }
          }
        }
      else
        event_type = demo_event_types[index % demo_event_types.length]
        payload = {
          id: format("seed_monthly_%03d_e%d", index + 1, endpoint_slot),
          type: event_type,
          data: {
            object: {
              title: format("Seed demo event %03d", index + 1),
              sequence: index + 1
            }
          }
        }
      end

      seed_inbound_event.call(
        endpoint: endpoint,
        token: endpoint_tokens.fetch(endpoint),
        event_id: payload[:id],
        event_type: event_type,
        payload: payload,
        request_id: format("seed-monthly-%03d", index + 1),
        received_at: received_at
      )
    end
  end
ensure
  RecordingStudioAccessible.configuration.access_management_authorizer = previous_access_authorizer
  Current.actor = previous_actor
end

puts "Seeded: admin@admin.com / Password"
puts "Seeded: Workspace '#{workspace.name}' with root recording ##{root_recording.id}"
puts "Seeded: Workspace '#{accessible_workspace.name}' with root recording ##{accessible_root_recording.id}"
puts "Seeded: Workspace '#{private_workspace.name}' with root recording ##{private_root_recording.id}"
puts "Seeded: Folder '#{folder.name}' and page '#{page.title}'"
if RecordingStudioWebhooks::Endpoint.table_exists?
  endpoint_count = RecordingStudioWebhooks::Endpoint.current
    .joins(:recording_studio_recording)
    .where(recording_studio_recordings: { root_recording_id: root_recording.id })
    .count
  token_count = RecordingStudioWebhooks::EndpointToken.current.count
  event_count = RecordingStudioWebhooks::InboundEvent
    .joins(endpoint: :recording_studio_recording)
    .where(recording_studio_recordings: { root_recording_id: root_recording.id })
    .count
  monthly_seed_count = RecordingStudioWebhooks::InboundEvent
    .joins(endpoint: :recording_studio_recording)
    .where(recording_studio_recordings: { root_recording_id: root_recording.id })
    .where("provider_event_id LIKE ?", "seed_monthly_%")
    .count

  puts "Seeded: #{endpoint_count} current webhook endpoints for Studio Workspace"
  puts "Seeded: #{token_count} active endpoint tokens"
  puts "Seeded: #{event_count} inbound webhook events across multiple endpoints"
  puts "Seeded: #{monthly_seed_count} monthly chart events"
end
