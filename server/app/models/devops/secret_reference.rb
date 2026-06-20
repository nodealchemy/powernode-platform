# frozen_string_literal: true

module Devops
  class SecretReference < ApplicationRecord
    self.table_name = "devops_secret_references"

    # Concerns
    include Auditable

    # Constants
    SECRET_TYPES = %w[ai_provider mcp_server chat_channel git_credential custom].freeze

    # Associations
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :name, uniqueness: { scope: :account_id }
    validates :secret_type, presence: true, inclusion: { in: SECRET_TYPES }
    validates :vault_path, presence: true, format: { with: %r{\Asecret/} }

    # Scopes
    scope :by_type, ->(type) { where(secret_type: type) }
    scope :expiring_soon, ->(days = 30) { where("expires_at IS NOT NULL AND expires_at <= ?", days.days.from_now) }
    scope :expired, -> { where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }
    scope :recently_accessed, ->(days = 7) { where("last_accessed_at >= ?", days.days.ago) }
    scope :needs_rotation, ->(days = 90) { where("last_rotated_at IS NULL OR last_rotated_at <= ?", days.days.ago) }

    # Access tracking
    def record_access!
      touch(:last_accessed_at)
    end

    def record_rotation!
      touch(:last_rotated_at)
    end

    # Status checks
    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def expiring_soon?(days = 30)
      expires_at.present? && expires_at <= days.days.from_now
    end

    def needs_rotation?(days = 90)
      last_rotated_at.nil? || last_rotated_at <= days.days.ago
    end

    # Vault operations
    def read_secret
      record_access!
      Security::VaultClient.read_secret(vault_path, key: vault_key)
    end

    def write_secret(data)
      Security::VaultClient.write_secret(vault_path, data)
      record_rotation!
    end

    def delete_secret
      Security::VaultClient.delete_secret(vault_path)
    end

    # Environment variable name
    def env_var_name
      "SECRET_#{name.upcase.gsub(/[^A-Z0-9]/, '_')}"
    end

    # Summary
    def reference_summary
      {
        id: id,
        name: name,
        secret_type: secret_type,
        vault_path: vault_path,
        vault_key: vault_key,
        description: description,
        expires_at: expires_at,
        expired: expired?,
        needs_rotation: needs_rotation?,
        last_accessed_at: last_accessed_at,
        last_rotated_at: last_rotated_at
      }
    end
  end
end
