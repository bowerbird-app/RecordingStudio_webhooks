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

seed_action_attempts = lambda do |event:, seed_index:, seed_total:, month_start:, month_span_seconds:|
  plans = event.action_plans.order(:execution_position).to_a
  return if plans.empty?

  pattern = [1, 1, 2, 1, 3, 2, 1, 4, 2, 1].freeze
  progress = seed_total <= 1 ? 0.0 : seed_index.to_f / (seed_total - 1)
  curved_progress = progress**1.35
  wave = Math.sin((seed_index + 1) * 1.7) * 0.08
  spread_ratio = [[curved_progress + wave, 0.0].max, 1.0].min
  base_time = month_start + (month_span_seconds * spread_ratio).seconds
  action_name_bases = if event.provider_name == "stripe"
                        %w[stripe.invoice_paid stripe.charge_settled]
                      else
                        %w[demo.received demo.created demo.updated]
                      end

  plans.each do |plan|
    position_offset = [plan.execution_position.to_i, 1].max - 1
    action_batch_index = (seed_index / 3)
    base_action_name = action_name_bases[(action_batch_index + position_offset) % action_name_bases.length]
    action_name = plans.length > 1 ? "#{base_action_name}.#{position_offset + 1}" : base_action_name
    attempts = [pattern[(seed_index + plan.execution_position) % pattern.length], 5].min
    status = if attempts >= 4 && ((seed_index + plan.execution_position) % 11).zero?
               "failed"
             elsif attempts >= 3 && ((seed_index + plan.execution_position) % 7).zero?
               "retrying"
             else
               "succeeded"
             end

    created_at = base_time + (position_offset * 7).minutes
    started_at = created_at + 2.minutes
    completed_at = status == "succeeded" || status == "failed" ? started_at + (attempts * 45).seconds : nil
    next_attempt_at = status == "retrying" ? started_at + 30.minutes : nil

    attempt_history = []
    attempts.times do |attempt_index|
      attempt_number = attempt_index + 1
      started_marker = started_at + (attempt_index * 45).seconds
      attempt_history << {
        "status" => "running",
        "at" => started_marker.iso8601,
        "attempt" => attempt_number
      }

      next if attempt_number == attempts

      attempt_history << {
        "status" => "retrying",
        "at" => (started_marker + 20.seconds).iso8601,
        "attempt" => attempt_number,
        "error" => "action_execution_failed"
      }
    end

    final_marker = completed_at || next_attempt_at || (started_at + (attempts * 45).seconds)
    attempt_history << {
      "status" => status,
      "at" => final_marker.iso8601,
      "attempt" => attempts,
      "error" => (status == "failed" ? "action_execution_failed" : nil)
    }.compact

    plan.class.where(id: plan.id).update_all(
      action_name: action_name,
      attempts: attempts,
      status: status,
      created_at: created_at,
      updated_at: final_marker,
      queued_at: created_at + 1.minute,
      started_at: started_at,
      completed_at: completed_at,
      next_attempt_at: next_attempt_at,
      last_error: (status == "failed" ? "action_execution_failed" : nil),
      action_snapshot: plan.action_snapshot.is_a?(Hash) ? plan.action_snapshot.merge("name" => action_name) : { "name" => action_name },
      attempt_history: attempt_history
    )
  end
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
    month_start = Time.current.utc.beginning_of_month
    month_end = [Time.current.utc.end_of_day, Time.current.utc.end_of_month.end_of_day].min
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

      event = seed_inbound_event.call(
        endpoint: endpoint,
        token: endpoint_tokens.fetch(endpoint),
        event_id: payload[:id],
        event_type: event_type,
        payload: payload,
        request_id: format("seed-monthly-%03d", index + 1),
        received_at: received_at
      )

      seed_action_attempts.call(
        event: event,
        seed_index: index,
        seed_total: events_to_seed,
        month_start: month_start,
        month_span_seconds: month_span_seconds
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
  monthly_seed_attempts = RecordingStudioWebhooks::ActionPlan
    .joins(inbound_event: { endpoint: :recording_studio_recording })
    .where(recording_studio_recordings: { root_recording_id: root_recording.id })
    .where("recording_studio_webhooks_inbound_events.provider_event_id LIKE ?", "seed_monthly_%")
    .sum(:attempts)

  puts "Seeded: #{endpoint_count} current webhook endpoints for Studio Workspace"
  puts "Seeded: #{token_count} active endpoint tokens"
  puts "Seeded: #{event_count} inbound webhook events across multiple endpoints"
  puts "Seeded: #{monthly_seed_count} monthly chart events"
  puts "Seeded: #{monthly_seed_attempts} monthly action attempts"
end
