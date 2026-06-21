# frozen_string_literal: true

class UserRole < ApplicationRecord
  # Table configuration
  self.table_name = "user_roles"
  self.primary_key = [ :user_id, :role_id ]

  # Associations
  belongs_to :user
  belongs_to :role
  belongs_to :granted_by_user, class_name: "User", foreign_key: :granted_by_id, optional: true

  # Validations
  validates :user_id, uniqueness: { scope: :role_id, message: "already has this role" }
  validate :role_available_to_user_account

  # Callbacks
  after_create :log_role_grant
  after_create :clear_user_permission_cache
  after_destroy :log_role_revoke
  after_destroy :clear_user_permission_cache

  private

  # A user may only hold GLOBAL roles (account_id nil) or roles owned by their
  # own account — never another account's custom role (cross-account isolation).
  def role_available_to_user_account
    return if role.nil? || user.nil?
    return if role.account_id.nil? || role.account_id == user.account_id

    errors.add(:role, "is not available to this user's account")
  end

  def log_role_grant
    Rails.logger.info "Role #{role.name} granted to user #{user.email}"
  end

  def log_role_revoke
    Rails.logger.info "Role #{role.name} revoked from user #{user.email}"
  end

  # Clear user's permission cache when their roles change
  def clear_user_permission_cache
    user.send(:clear_permission_cache) if user
  end
end
