# frozen_string_literal: true

require "test_helper"

class AuthorizeWriteTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "write-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @workspace = Workspace.create!(name: "Write #{SecureRandom.hex(4)}")
    @root = RecordingStudio.create_root_recording!(@workspace, actor: @user)
    @previous_actor = Current.actor
    Current.actor = @user
  end

  teardown do
    Current.actor = @previous_actor
  end

  test "root_recording_for finds a root and create_root_recording! creates one" do
    workspace = Workspace.create!(name: "Root split #{SecureRandom.hex(4)}")

    assert_nil RecordingStudio.root_recording_for(workspace)

    created = RecordingStudio.create_root_recording!(workspace, actor: @user)
    assert_predicate created, :persisted?
    assert_nil created.parent_recording_id
    assert_equal created, RecordingStudio.root_recording_for(workspace)

    again = RecordingStudio.create_root_recording!(workspace, actor: @user)
    assert_equal created.id, again.id

    events = RecordingStudio::Event.where(recording_id: created.id, action: "created")
    assert_equal 1, events.count
    assert_equal created.id, events.pick(:root_recording_id)
  end

  test "AccessCreationContext does not authorize ordinary page writes" do
    RecordingStudioAccessible::AccessCreationContext.allow do
      assert_raises(RecordingStudio::AuthorizationError) do
        RecordingStudio.record!(
          action: "created",
          recordable: Page.new(title: "Blocked by write gate #{SecureRandom.hex(4)}"),
          root_recording: @root,
          parent_recording: @root,
          actor: @user
        )
      end
    end
  end

  test "page writes succeed after Accessible edit access on the root" do
    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: @root,
      actor: @user
    )
    raise result.error if result.failure?

    title = "Allowed page #{SecureRandom.hex(4)}"
    RecordingStudio.record!(
      action: "created",
      recordable: Page.new(title: title),
      root_recording: @root,
      parent_recording: @root,
      actor: @user
    )

    page = Page.find_by!(title: title)
    assert_predicate RecordingStudio::Recording.find_by(root_recording: @root, recordable: page, trashed_at: nil), :present?
  end
end
