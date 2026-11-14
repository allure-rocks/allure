# frozen_string_literal: true

require "digest"

encryption = Rails.application.config.active_record.encryption
key_names = %w[
  ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
  ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
  ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
].freeze

if Rails.env.production?
  missing = key_names.select { |name| ENV[name].blank? }
  raise "Missing Active Record Encryption configuration: #{missing.join(", ")}" if missing.any?
end

secret = Rails.application.secret_key_base.presence || "allure-development-encryption"
derive_key = ->(purpose) { Digest::SHA256.digest("#{secret}:#{purpose}") }

encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence || derive_key.call("primary")
encryption.deterministic_key =
  ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence || derive_key.call("deterministic")
encryption.key_derivation_salt =
  ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence || derive_key.call("salt")
