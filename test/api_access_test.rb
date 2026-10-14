# frozen_string_literal: true

require "test_helper"
require "recording_studio_admin"
require "recording_studio_accessible"

class ApiAccessTest < Minitest::Test
  Grant = Struct.new(:actor)
  GrantContext = Struct.new(:access_grant)

  def test_can_view_prefers_the_site_resolver_when_it_is_set
    viewer = Object.new
    site_recording = Object.new
    access_called = false

    with_admin_resolvers(
      site: lambda { |context|
        assert_nil context.controller
        site_recording
      },
      access: lambda { |_context|
        access_called = true
        Object.new
      }
    ) do
      allow_site = lambda do |actor:, recording:, role:|
        actor.equal?(viewer) && recording.equal?(site_recording) && role == :view
      end

      RecordingStudioAccessible.stub(:authorized?, allow_site) do
        assert RecordingStudioWebhooks::Api::Access.can_view?(grant_context(viewer))
      end
    end

    refute access_called
  end

  def test_can_view_falls_back_to_the_access_resolver
    viewer = Object.new
    access_recording = Object.new

    with_admin_resolvers(site: nil, access: ->(_context) { access_recording }) do
      allow_access = lambda do |actor:, recording:, role:|
        actor.equal?(viewer) && recording.equal?(access_recording) && role == :view
      end

      RecordingStudioAccessible.stub(:authorized?, allow_access) do
        assert RecordingStudioWebhooks::Api::Access.can_view?(grant_context(viewer))
      end
    end
  end

  def test_can_view_denies_when_the_resolver_raises
    viewer = Object.new
    access_called = false

    with_admin_resolvers(
      site: ->(context) { context.controller.current_root_recording },
      access: lambda { |_context|
        access_called = true
        Object.new
      }
    ) do
      decision = nil

      RecordingStudioAccessible.stub(:authorized?, ->(**) { flunk "Accessible should not be checked" }) do
        decision = RecordingStudioWebhooks::Api::Access.can_view?(grant_context(viewer))
      end

      refute decision
    end

    refute access_called
  end

  def test_can_view_denies_when_the_resolver_returns_nil
    viewer = Object.new
    access_called = false

    with_admin_resolvers(
      site: ->(_context) {},
      access: lambda { |_context|
        access_called = true
        Object.new
      }
    ) do
      RecordingStudioAccessible.stub(:authorized?, ->(**) { flunk "Accessible should not be checked" }) do
        refute RecordingStudioWebhooks::Api::Access.can_view?(grant_context(viewer))
      end
    end

    refute access_called
  end

  private

  def grant_context(actor)
    GrantContext.new(Grant.new(actor))
  end

  def with_admin_resolvers(site:, access:)
    config = RecordingStudioAdmin.configuration
    previous_site = config.site_admin_recording_resolver
    previous_access = config.access_recording_resolver
    config.site_admin_recording_resolver = site
    config.access_recording_resolver = access
    yield
  ensure
    config.site_admin_recording_resolver = previous_site
    config.access_recording_resolver = previous_access
  end
end
