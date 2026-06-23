# frozen_string_literal: true

class RolePermission < ApplicationRecord
  # Table configuration
  self.table_name = "role_permissions"

  # Associations
  belongs_to :role

  # Validations
  # Permissions are code-defined (the Permissions catalog is the source of
  # truth); a grant references a catalog permission by name, not a DB row.
  validates :permission_name, presence: true
  validates :role_id, uniqueness: { scope: :permission_name, message: "has already been taken" }
  validate :permission_must_exist_in_catalog

  # Callbacks
  after_create :log_permission_grant
  after_destroy :log_permission_revoke
  after_commit :invalidate_user_permission_caches

  private

  def permission_must_exist_in_catalog
    return if permission_name.blank?
    return if Permissions.permission_exists?(permission_name)

    errors.add(:permission_name, "is not a defined permission")
  end

  def log_permission_grant
    Rails.logger.info "Permission #{permission_name} granted to role #{role.name}"
  end

  def log_permission_revoke
    Rails.logger.info "Permission #{permission_name} revoked from role #{role.name}"
  end

  # When permissions on a role change, invalidate cached permissions for all users with that role
  def invalidate_user_permission_caches
    role.users.find_each(&:touch)
  rescue StandardError => e
    Rails.logger.warn "Failed to invalidate permission caches for role #{role_id}: #{e.message}"
  end
end
