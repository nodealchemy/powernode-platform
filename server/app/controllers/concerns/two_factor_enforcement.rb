# frozen_string_literal: true

# Concern for enforcing 2FA on sensitive operations
# CRITICAL: Admin users MUST have 2FA enabled
module TwoFactorEnforcement
  extend ActiveSupport::Concern

  included do
    before_action :enforce_two_factor_for_admins
    before_action :enforce_two_factor_for_sensitive_actions
  end

  # Actions that require 2FA regardless of user role
  SENSITIVE_ACTIONS = %w[
    destroy
    impersonate
    manage_roles
    update_permissions
    update_billing
    cancel_subscription
    export_data
    delete_account
    change_password
    generate_api_key
    revoke_api_key
  ].freeze

  # Permissions that require 2FA to be enabled
  ADMIN_PERMISSIONS = %w[
    system.admin
    accounts.manage
    users.manage
    billing.manage
    security.manage
    audit_logs.export
    data.export
  ].freeze

  private

  def enforce_two_factor_for_admins
    return unless current_user
    return if two_factor_verified?
    return unless requires_admin_two_factor?

    render_two_factor_required('Admin users must enable two-factor authentication')
  end

  def enforce_two_factor_for_sensitive_actions
    return unless current_user
    return if two_factor_verified?
    return unless sensitive_action?

    render_two_factor_required('This action requires two-factor authentication')
  end

  def requires_admin_two_factor?
    return false unless current_user

    ADMIN_PERMISSIONS.any? { |perm| current_user.has_permission?(perm) }
  end

  def sensitive_action?
    SENSITIVE_ACTIONS.include?(action_name)
  end

  def two_factor_verified?
    return false unless current_user
    return false unless current_user.two_factor_enabled?

    # Check if 2FA was verified in current session
    # This is stored in the JWT or session
    two_factor_verified_at = decoded_token&.dig('two_factor_verified_at')
    return false if two_factor_verified_at.blank?

    # 2FA verification is valid for 24 hours
    Time.zone.parse(two_factor_verified_at) > 24.hours.ago
  rescue StandardError
    false
  end

  def render_two_factor_required(message = nil)
    if current_user.two_factor_enabled?
      # User has 2FA enabled but hasn't verified this session
      render json: {
        success: false,
        error: message || 'Two-factor authentication required',
        code: 'TWO_FACTOR_REQUIRED',
        requires_verification: true
      }, status: :forbidden
    else
      # User doesn't have 2FA enabled - must set it up first
      render json: {
        success: false,
        error: message || 'You must enable two-factor authentication to access this resource',
        code: 'TWO_FACTOR_SETUP_REQUIRED',
        requires_setup: true,
        setup_url: '/api/v1/auth/two_factor/setup'
      }, status: :forbidden
    end
  end

  def decoded_token
    @decoded_token ||= begin
      token = request.headers['Authorization']&.split(' ')&.last
      return nil unless token

      JsonWebToken.decode(token)
    rescue StandardError
      nil
    end
  end
end

# Concern for User model to enforce 2FA requirements
module RequiresTwoFactor
  extend ActiveSupport::Concern

  included do
    validate :two_factor_required_for_admin_roles, on: :update
  end

  # Admin roles that REQUIRE 2FA
  ADMIN_ROLE_NAMES = %w[
    super_admin
    admin
    system.admin
    account.manager
  ].freeze

  def must_have_two_factor?
    return false unless persisted?

    # Check if user has any admin roles
    has_admin_role? || has_admin_permissions?
  end

  def two_factor_enforcement_status
    if must_have_two_factor?
      if two_factor_enabled?
        :compliant
      else
        :required
      end
    else
      if two_factor_enabled?
        :enabled
      else
        :optional
      end
    end
  end

  def days_until_two_factor_required
    return nil unless must_have_two_factor? && !two_factor_enabled?

    # Give users 7 days to enable 2FA after becoming admin
    admin_since = admin_role_assigned_at
    return 7 unless admin_since

    days_left = 7 - ((Time.current - admin_since) / 1.day).to_i
    [days_left, 0].max
  end

  private

  def two_factor_required_for_admin_roles
    return unless must_have_two_factor?
    return if two_factor_enabled?

    # Check if grace period has expired
    if days_until_two_factor_required&.zero?
      errors.add(:base, 'Two-factor authentication is required for admin users')
    end
  end

  def has_admin_role?
    return false unless respond_to?(:roles)

    roles.any? { |role| ADMIN_ROLE_NAMES.include?(role.name) }
  end

  def has_admin_permissions?
    return false unless respond_to?(:has_permission?)

    TwoFactorEnforcement::ADMIN_PERMISSIONS.any? { |perm| has_permission?(perm) }
  end

  def admin_role_assigned_at
    return nil unless respond_to?(:user_roles)

    admin_user_role = user_roles.joins(:role)
                                .where(roles: { name: ADMIN_ROLE_NAMES })
                                .order(created_at: :asc)
                                .first

    admin_user_role&.created_at
  end
end
