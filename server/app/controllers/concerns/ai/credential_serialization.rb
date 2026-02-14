# frozen_string_literal: true

module Ai
  module CredentialSerialization
    extend ActiveSupport::Concern

    private

    def serialize_credential(credential)
      {
        id: credential.id,
        name: credential.name,
        is_active: credential.is_active,
        is_default: credential.is_default,
        last_used_at: credential.last_used_at&.iso8601,
        last_test_at: credential.last_test_at&.iso8601,
        last_test_status: credential.last_test_status,
        created_at: credential.created_at.iso8601,
        updated_at: credential.updated_at.iso8601,
        provider: {
          id: credential.provider.id,
          name: credential.provider.name,
          provider_type: credential.provider.provider_type
        },
        stats: {
          success_count: credential.success_count,
          failure_count: credential.failure_count,
          success_rate: calculate_credential_success_rate(credential)
        }
      }
    end

    def serialize_credential_detail(credential)
      result = serialize_credential(credential).merge(
        credential_keys: credential.credentials&.keys || []
      )

      if current_user&.has_permission?("ai.credentials.decrypt")
        result[:credentials] = credential.credentials
      end

      result
    end

    def calculate_credential_success_rate(credential)
      total = credential.success_count + credential.failure_count
      return 0 if total.zero?

      ((credential.success_count.to_f / total) * 100).round(2)
    end
  end
end
