# frozen_string_literal: true

class Account::DelegationPermission < ApplicationRecord
    self.table_name = "delegation_permissions"

    # Associations
    belongs_to :account_delegation, class_name: "Account::Delegation", foreign_key: "account_delegation_id"

    # Validations
    # Permissions are code-defined; a delegation references a catalog permission
    # by name (no DB permission row).
    validates :permission_name, presence: true
    validates :account_delegation_id, uniqueness: { scope: :permission_name,
                                                  message: "already has this permission assigned" }

    # Callbacks
    before_create :validate_permission_scope

    # Scopes
    scope :for_delegation, ->(delegation) { where(account_delegation: delegation) }

    # Class methods
    def self.permission_summary(delegation)
      names = where(account_delegation: delegation).pluck(:permission_name).sort
      # Group "resource.sub.action" by everything-but-the-last-segment -> action
      names.group_by { |n| n.split(".")[0..-2].join(".") }.transform_values do |perms|
        perms.map { |n| n.split(".").last }
      end
    end

    # Instance methods
    def permission_key
      permission_name
    end

    def permission_description
      Permissions.permission_description(permission_name)
    end

    private

    def validate_permission_scope
      # Ensure the permission being assigned doesn't exceed the delegation role's permissions
      delegation_role = account_delegation.role
      return if delegation_role.blank?

      unless delegation_role.has_permission?(permission_name)
        errors.add(:permission_name, "cannot be granted as it's not available in the delegation's role")
        throw :abort
      end
  end
end
