# frozen_string_literal: true

# Layered encryption: Rails `encrypts` (at-rest) + Vault transit pepper
# (per-account). Sensitive credentials are protected against compromise of
# either the database alone OR Vault transit alone — both are required to
# recover plaintext.
#
# Usage:
#
#   class System::ProviderConnection < BaseRecord
#     include AccountPepperedEncryption
#     encrypts :access_key                       # Rails at-rest encryption
#     encrypts :secret_key
#     peppered_attribute :access_key, :secret_key
#   end
#
# Read path:
#   column → Rails decrypt (super) → if peppered blob → Vault transit decrypt → plaintext.
#   Legacy un-peppered values flow through unchanged.
#
# Write path:
#   plaintext → Vault transit encrypt → Rails encrypt (super) → column.
#   When Vault transit is unavailable, falls back to plaintext (Rails encrypts
#   still wraps it). Next read works because the un-peppered branch handles
#   raw values.
#
# Internals:
#   Uses Module#prepend so `super` invokes the Rails-encrypts accessors. This
#   sidesteps the timing issue where `method_defined?` doesn't see methods
#   that `encrypts` registers via the attribute API.
#
# Reference: comprehensive stabilization sweep P3 + docs/system/credential-restoration.md.
module AccountPepperedEncryption
  extend ActiveSupport::Concern

  class_methods do
    def peppered_attribute(*attr_names)
      override_module = Module.new
      attr_names.each do |attr_name|
        override_module.module_eval do
          define_method("#{attr_name}=") do |plaintext|
            wrapped =
              begin
                if plaintext.present? && account.present?
                  ::Security::AccountEncryptionKeyService.peppered(account, plaintext)
                else
                  plaintext
                end
              rescue ::Security::VaultTransitClient::VaultUnavailableError => e
                Rails.logger.warn "[AccountPepperedEncryption] Vault unavailable on write to #{self.class.name}##{attr_name}; storing un-peppered: #{e.message}"
                plaintext
              end

            super(wrapped)
          end

          define_method(attr_name) do
            raw = super()
            return raw if raw.blank?

            if account.present? && ::Security::AccountEncryptionKeyService.peppered_blob?(raw)
              begin
                ::Security::AccountEncryptionKeyService.decrypt(account, raw)
              rescue ::Security::VaultTransitClient::VaultUnavailableError => e
                Rails.logger.error "[AccountPepperedEncryption] Vault unavailable on read from #{self.class.name}##{attr_name}: #{e.message}"
                raise
              end
            else
              raw # legacy un-peppered value, return as-is
            end
          end
        end
      end

      prepend(override_module)
    end
  end
end
