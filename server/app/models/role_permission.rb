# frozen_string_literal: true

class RolePermission < ApplicationRecord
  # Table configuration
  self.table_name = "role_permissions"

  # Associations
  belongs_to :role
  belongs_to :permission

  # Validations
  validates :role_id, uniqueness: { scope: :permission_id, message: "has already been taken" }

  # Callbacks
  after_create :log_permission_grant
  after_destroy :log_permission_revoke
  after_commit :invalidate_user_permission_caches

  private

  def log_permission_grant
    Rails.logger.info "Permission #{permission.name} granted to role #{role.name}"
  end

  def log_permission_revoke
    Rails.logger.info "Permission #{permission.name} revoked from role #{role.name}"
  end

  # When permissions on a role change, invalidate cached permissions for all users with that role
  def invalidate_user_permission_caches
    role.users.find_each(&:touch)
  rescue StandardError => e
    Rails.logger.warn "Failed to invalidate permission caches for role #{role_id}: #{e.message}"
  end
end
