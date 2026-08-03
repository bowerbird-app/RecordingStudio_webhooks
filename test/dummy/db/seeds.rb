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

evenly_distributed_time = lambda do |index:, total:, range_start:, range_span_seconds:|
  return range_start if total <= 1

  offset_seconds = (range_span_seconds * index.to_f / (total - 1)).round
  range_start + offset_seconds.seconds
end

apply_plan_state = lambda do |plan:, status:, created_at:, attempts:, action_name:, error_code: nil|
  started_at = created_at + 2.minutes
  queued_at = created_at + 1.minute
  completed_at = nil
  next_attempt_at = nil
  last_error = nil
  final_at = started_at + 20.seconds

  case status
  when "succeeded"
    completed_at = started_at + (attempts * 35).seconds
    final_at = completed_at
  when "failed"
    completed_at = started_at + (attempts * 45).seconds
    final_at = completed_at
    last_error = error_code || "action_execution_failed"
  when "retrying"
    next_attempt_at = started_at + 45.minutes
    final_at = next_attempt_at
    last_error = error_code || "dispatch_unavailable"
  when "running"
    final_at = started_at + 90.seconds
  when "queued"
    final_at = queued_at + 20.seconds
  when "pending"
    final_at = created_at + 20.seconds
  when "skipped", "cancelled"
    completed_at = started_at + 30.seconds
    final_at = completed_at
  end

  attempt_history = []
  [attempts, 1].max.times do |attempt_index|
    attempt_number = attempt_index + 1
    marker = started_at + (attempt_index * 35).seconds
    attempt_history << {
      "status" => "running",
      "at" => marker.iso8601,
      "attempt" => attempt_number
    }
  end
  attempt_history << {
    "status" => status,
    "at" => final_at.iso8601,
    "attempt" => [attempts, 1].max,
    "error" => last_error
  }.compact

  plan.class.where(id: plan.id).update_all(
    action_name: action_name,
    status: status,
    attempts: attempts,
    created_at: created_at,
    updated_at: final_at,
    queued_at: queued_at,
    started_at: started_at,
    completed_at: completed_at,
    next_attempt_at: next_attempt_at,
    last_error: last_error,
    action_snapshot: plan.action_snapshot.is_a?(Hash) ? plan.action_snapshot.merge("name" => action_name) : { "name" => action_name },
    attempt_history: attempt_history
  )
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
previous_dispatcher = RecordingStudioWebhooks.configuration.dispatcher
RecordingStudioWebhooks.configuration.dispatcher = ->(_plan_id, wait_until: nil) { true }

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
      label: "Demonstration Hyperextended Observability Aggregation EndpointBeta",
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

    failed_target_count = 100
    non_failed_target_count = 300
    total_monthly_seeds = failed_target_count + non_failed_target_count
    range_start = Time.current.utc.prev_month.beginning_of_month
    range_end = Time.current.utc.end_of_day
    range_span_seconds = [(range_end - range_start).to_i, 1].max

    monthly_event_scope = RecordingStudioWebhooks::InboundEvent
      .joins(endpoint: :recording_studio_recording)
      .where(recording_studio_recordings: { root_recording_id: root_recording.id })
      .where("recording_studio_webhooks_inbound_events.provider_event_id LIKE ?", "seed_monthly_%")
    monthly_event_ids = monthly_event_scope.pluck(:id)
    unless monthly_event_ids.empty?
      RecordingStudioWebhooks::ActionPlan.where(inbound_event_id: monthly_event_ids).delete_all
      RecordingStudioWebhooks::InboundEvent.where(id: monthly_event_ids).delete_all
    end

    demo_endpoints = seeded_endpoints.select { |endpoint| endpoint.provider_name == "demo" }
    demo_endpoints = seeded_endpoints if demo_endpoints.empty?

    failed_target_count.times do |index|
      endpoint = demo_endpoints[index % demo_endpoints.length]
      received_at = evenly_distributed_time.call(
        index: index,
        total: failed_target_count,
        range_start: range_start,
        range_span_seconds: range_span_seconds
      )
      event_id = format("seed_monthly_failed_%03d", index + 1)
      payload = {
        id: event_id,
        type: "demo.received",
        data: {
          object: {
            title: format("Seed failed event %03d", index + 1),
            sequence: index + 1
          }
        }
      }

      event = seed_inbound_event.call(
        endpoint: endpoint,
        token: endpoint_tokens.fetch(endpoint),
        event_id: event_id,
        event_type: "demo.received",
        payload: payload,
        request_id: format("seed-monthly-failed-%03d", index + 1),
        received_at: received_at
      )
      plan = event.action_plans.order(:execution_position).first
      raise "Failed seed event missing action plan: #{event_id}" unless plan

      apply_plan_state.call(
        plan: plan,
        status: "failed",
        created_at: received_at + 20.seconds,
        attempts: 3 + (index % 2),
        action_name: "demo.received.failed",
        error_code: "action_execution_failed"
      )
    end

    non_failed_statuses = %w[succeeded retrying queued running pending skipped cancelled].freeze
    non_failed_target_count.times do |index|
      endpoint = demo_endpoints[(index + 1) % demo_endpoints.length]
      received_at = evenly_distributed_time.call(
        index: index,
        total: non_failed_target_count,
        range_start: range_start,
        range_span_seconds: range_span_seconds
      )
      event_id = format("seed_monthly_nonfailed_%03d", index + 1)
      event_type = "demo.received"
      payload = {
        id: event_id,
        type: event_type,
        data: {
          object: {
            title: format("Seed non-failed event %03d", index + 1),
            sequence: failed_target_count + index + 1
          }
        }
      }

      event = seed_inbound_event.call(
        endpoint: endpoint,
        token: endpoint_tokens.fetch(endpoint),
        event_id: event_id,
        event_type: event_type,
        payload: payload,
        request_id: format("seed-monthly-nonfailed-%03d", index + 1),
        received_at: received_at
      )
      plan = event.action_plans.order(:execution_position).first
      raise "Non-failed seed event missing action plan: #{event_id}" unless plan

      status = non_failed_statuses[(index / 9 + index) % non_failed_statuses.length]
      attempts = case status
                 when "pending" then 0
                 when "queued" then 1
                 when "running" then 1
                 when "retrying" then 2
                 else 1 + ((index % 4).zero? ? 1 : 0)
                 end
      apply_plan_state.call(
        plan: plan,
        status: status,
        created_at: received_at + 20.seconds,
        attempts: attempts,
        action_name: "demo.received.non_failed"
      )
    end

    monthly_plan_scope = RecordingStudioWebhooks::ActionPlan
      .joins(inbound_event: { endpoint: :recording_studio_recording })
      .where(recording_studio_recordings: { root_recording_id: root_recording.id })
      .where("recording_studio_webhooks_inbound_events.provider_event_id LIKE ?", "seed_monthly_%")
    failed_seed_count = monthly_plan_scope.where(status: "failed").count
    non_failed_seed_count = monthly_plan_scope.where.not(status: "failed").count

    puts "Seeded: #{total_monthly_seeds} monthly events"
    puts "Seeded: #{failed_seed_count} monthly failed action plans"
    puts "Seeded: #{non_failed_seed_count} monthly non-failed action plans"
  end
ensure
  RecordingStudioWebhooks.configuration.dispatcher = previous_dispatcher
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
  monthly_failed_plans = RecordingStudioWebhooks::ActionPlan
    .joins(inbound_event: { endpoint: :recording_studio_recording })
    .where(recording_studio_recordings: { root_recording_id: root_recording.id })
    .where("recording_studio_webhooks_inbound_events.provider_event_id LIKE ?", "seed_monthly_%")
    .where(status: "failed")
    .count
  monthly_non_failed_plans = RecordingStudioWebhooks::ActionPlan
    .joins(inbound_event: { endpoint: :recording_studio_recording })
    .where(recording_studio_recordings: { root_recording_id: root_recording.id })
    .where("recording_studio_webhooks_inbound_events.provider_event_id LIKE ?", "seed_monthly_%")
    .where.not(status: "failed")
    .count

  puts "Seeded: #{endpoint_count} current webhook endpoints for Studio Workspace"
  puts "Seeded: #{token_count} active endpoint tokens"
  puts "Seeded: #{event_count} inbound webhook events across multiple endpoints"
  puts "Seeded: #{monthly_seed_count} monthly chart events"
  puts "Seeded: #{monthly_seed_attempts} monthly action attempts"
  puts "Seeded: #{monthly_failed_plans} monthly failed action plans"
  puts "Seeded: #{monthly_non_failed_plans} monthly non-failed action plans"
end
