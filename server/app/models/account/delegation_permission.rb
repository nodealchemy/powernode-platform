# frozen_string_literal: true

class Account::DelegationPermission < ApplicationRecord
    self.table_name = "delegation_permissions"

    # Associations
    belongs_to :account_delegation, class_name: "Account::Delegation", foreign_key: "account_delegation_id"
    belongs_to :permission

    # Validations
    validates :account_delegation_id, uniqueness: { scope: :permission_id,
                                                  message: "already has this permission assigned" }

    # Callbacks
    before_create :validate_permission_scope

    # Scopes
    scope :for_delegation, ->(delegation) { where(account_delegation: delegation) }
    scope :by_resource, ->(resource) { joins(:permission).where(permissions: { resource: resource }) }
    scope :by_action, ->(action) { joins(:permission).where(permissions: { action: action }) }

    # Class methods
    def self.permission_summary(delegation)
      permissions = joins(:permission)
                     .where(account_delegation: delegation)
                     .includes(:permission)
                     .order("permissions.resource, permissions.action")

      grouped = permissions.group_by { |dp| dp.permission.resource }

      grouped.transform_values do |perms|
        perms.map { |dp| dp.permission.action }
      end
    end

    # Instance methods
    def permission_key
      "#{permission.resource}.#{permission.action}"
    end

    def permission_description
      permission.description
    end

    private

    def validate_permission_scope
      # Ensure the permission being assigned doesn't exceed the role's permissions
      delegation_role = account_delegation.role

      if delegation_role.present?
      unless delegation_role.permissions.include?(permission)
        errors.add(:permission, "cannot be granted as it's not available in the delegation's role")
        throw :abort
      end
      end
  end
end
