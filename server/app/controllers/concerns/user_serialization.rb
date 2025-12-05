# frozen_string_literal: true

# User serialization concern that provides consistent user data formatting
# Includes permissions array for frontend access control
module UserSerialization
  extend ActiveSupport::Concern

  private

  # Standard user data serialization with permissions
  def user_data(user)
    return nil unless user

    {
      id: user.id,
      name: user.name,
      full_name: user.full_name,
      email: user.email,
      email_verified: user.email_verified?,
      
      # Keep roles for display and backend processing
      roles: user.role_names,
      
      # ADD: permissions array for frontend access control
      permissions: user_permissions(user),
      
      status: user.status,
      locked: user.locked?,
      failed_login_attempts: user.failed_login_attempts,
      last_login_at: user.last_login_at,
      created_at: user.created_at,
      updated_at: user.updated_at,
      preferences: user.preferences || {},
      
      account: user.account ? account_data(user.account) : nil
    }
  end

  # Account data for user serialization
  def account_data(account)
    {
      id: account.id,
      name: account.name,
      status: account.status,
      subdomain: account.subdomain
    }
  end

  # Get permissions array from user model
  def user_permissions(user)
    user.permission_names
  end

  # Lightweight user data for lists and references
  def user_summary(user)
    return nil unless user

    {
      id: user.id,
      name: user.name,
      full_name: user.full_name,
      email: user.email,
      roles: user.role_names,
      permissions: user_permissions(user),
      status: user.status
    }
  end

  # User data for admin contexts with additional details
  def admin_user_data(user)
    base_data = user_data(user)
    return base_data unless base_data

    base_data.merge(
      two_factor_enabled: user.two_factor_enabled?,
      password_changed_at: user.password_changed_at,
      last_login_ip: user.last_login_ip,
      created_by: user.created_by ? user_summary(user.created_by) : nil
    )
  end

  # Check if current user has permission to view sensitive user data
  def can_view_sensitive_data?(target_user)
    return true if current_user&.has_permission?('admin.users.view')
    return true if current_user&.has_permission?('users.manage') && same_account?(target_user)
    return true if current_user == target_user
    false
  end

  # Check if users are in the same account
  def same_account?(other_user)
    current_user&.account_id == other_user&.account_id
  end
end