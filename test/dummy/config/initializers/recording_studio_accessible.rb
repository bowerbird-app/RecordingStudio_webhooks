# frozen_string_literal: true

RecordingStudioAccessible.configure do |config|
  config.access_actor_types = [ "User" ]

  # Kept admin root. Site-wide admin screens and webhook API access use this
  # recording. A missing root fails closed. Lookup only: seeds create it.
  config.admin_root_resolver = lambda do |**|
    admin_root = AdminRoot.find_by(name: "Admin")
    next unless admin_root

    RecordingStudio.root_recording_for(admin_root)
  end
end
