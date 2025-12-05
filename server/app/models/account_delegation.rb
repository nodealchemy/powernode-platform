# frozen_string_literal: true

class AccountDelegation < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :delegated_user, class_name: 'User', foreign_key: 'delegated_user_id'
  belongs_to :delegated_by, class_name: 'User', foreign_key: 'delegated_by_id'
  belongs_to :revoked_by, class_name: 'User', foreign_key: 'revoked_by_id', optional: true
  belongs_to :role, optional: true
  
  # Permission associations
  has_many :delegation_permissions, dependent: :destroy
  has_many :permissions, through: :delegation_permissions

  # Validations
  validates :delegated_by_id, uniqueness: { scope: [:account_id, :delegated_user_id], 
                                           message: "has already delegated to this user for this account" }
  validates :status, presence: true, inclusion: { in: %w[active inactive revoked] }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :inactive, -> { where(status: 'inactive') }
  scope :revoked, -> { where(status: 'revoked') }
  scope :for_account, ->(account) { where(account: account) }
  scope :for_user, ->(user) { where(delegated_user: user) }
  scope :not_expired, -> { where('expires_at IS NULL OR expires_at >= ?', Time.current) }
  scope :expired, -> { where('expires_at IS NOT NULL AND expires_at < ?', Time.current) }
  scope :with_role, ->(role) { where(role: role) }
  scope :by_role_name, ->(role_name) { joins(:role).where(roles: { name: role_name }) }

  # Callbacks
  before_create :set_defaults

  # State management
  def active?
    status == 'active' && !expired?
  end

  def inactive?
    status == 'inactive'
  end

  def revoked?
    status == 'revoked'
  end

  def expired?
    expires_at && expires_at < Time.current
  end

  def activate!
    update!(status: 'active')
  end

  def deactivate!
    update!(status: 'inactive')
  end

  def revoke!(revoked_by_user)
    update!(status: 'revoked', revoked_at: Time.current, revoked_by: revoked_by_user)
  end

  # Permission methods
  def can_manage_account?
    active? && (role&.name == 'Admin' || role&.name == 'Owner')
  end

  def can_view_analytics?
    active? && role&.has_permission?('analytics.read')
  end

  def can_manage_users?
    active? && role&.has_permission?('users.create')
  end

  def effective_permissions
    return [] unless active?
    
    # If specific permissions are assigned, use those
    if permissions.any?
      permissions
    elsif role.present?
      # Otherwise fall back to role permissions
      role.permissions
    else
      []
    end
  end

  # Display helpers
  def role_display_name
    role&.name || 'No Role'
  end

  def status_display
    case status
    when 'active'
      expired? ? 'Expired' : 'Active'
    when 'inactive'
      'Inactive'
    when 'revoked'
      'Revoked'
    else
      status.humanize
    end
  end

  def expires_in_days
    return nil unless expires_at
    ((expires_at - Time.current) / 1.day).ceil
  end

  # Permission management methods
  def has_permission?(permission_key)
    return false unless active?
    
    if permission_key.is_a?(String) && permission_key.include?('.')
      resource, action = permission_key.split('.', 2)
      effective_permissions.any? { |p| p.resource == resource && p.action == action }
    else
      effective_permissions.any? { |p| p.name == permission_key }
    end
  end

  def assign_permission(permission)
    return false unless active?
    return false if has_permission?("#{permission.resource}.#{permission.action}")
    
    # Validate permission is within role scope if role is assigned
    if role.present? && !role.permissions.include?(permission)
      return false
    end
    
    delegation_permissions.create(permission: permission)
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def remove_permission(permission)
    delegation_permission = delegation_permissions.find_by(permission: permission)
    delegation_permission&.destroy
  end

  def permission_source
    if permissions.any?
      'custom'
    elsif role.present?
      'role'
    else
      'none'
    end
  end

  def available_permissions
    return [] unless role.present?
    
    # Return role permissions that aren't already specifically assigned
    assigned_permission_ids = delegation_permissions.pluck(:permission_id)
    role.permissions.where.not(id: assigned_permission_ids)
  end

  def permissions_summary
    return 'No permissions' unless effective_permissions.any?
    
    grouped = effective_permissions.group_by(&:resource)
    summary_parts = grouped.map do |resource, perms|
      actions = perms.map(&:action).sort
      "#{resource}: #{actions.join(', ')}"
    end
    
    summary_parts.join(' | ')
  end

  private

  def set_defaults
    self.status = 'active' if status.blank?
  end
end