# frozen_string_literal: true

# Dummy-only. Hosts set Active Record encryption keys in credentials. Rails
# copies those credentials into Active Record encryption before initializers
# run. When the keys are still blank, derive them from the local
# secret_key_base so endpoint signing secrets can be stored. These derived
# keys are not a committed secret.
ActiveSupport.on_load(:active_record_encryption) do
  next if ActiveRecord::Encryption.config.has_primary_key?

  material = Rails.application.secret_key_base.to_s
  derive = lambda do |label|
    OpenSSL::HMAC.hexdigest("SHA256", material, "recording-studio-webhooks-dummy-#{label}")
  end

  ActiveRecord::Encryption.configure(
    primary_key: derive.call("primary"),
    deterministic_key: derive.call("deterministic"),
    key_derivation_salt: derive.call("salt")
  )
end
