# frozen_string_literal: true

# User model with new permission system
class User < ApplicationRecord
  # PII Encryption - GDPR/SOC2 Compliance
  # Deterministic encryption for email allows querying (find_by email)
  # Non-deterministic encryption for other PII fields (more secure)
  encrypts :email, deterministic: true, downcase: true
  encrypts :name
  encrypts :two_factor_secret
  encrypts :backup_codes
  encrypts :last_login_ip

  # Authentication
  has_secure_password

  # Include concerns - must come after has_secure_password
  include PasswordSecurity
  include Auditable

  # Attributes
  attr_reader :reset_token

  # Associations
  belongs_to :account
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :audit_logs, dependent: :nullify
  has_many :password_histories, dependent: :destroy
  has_many :pages, foreign_key: "author_id", dependent: :destroy
  has_many :impersonation_sessions_as_impersonator,
           class_name: "ImpersonationSession",
           foreign_key: "impersonator_id",
           dependent: :destroy
  has_many :impersonation_sessions_as_target,
           class_name: "ImpersonationSession",
           foreign_key: "impersonated_user_id",
           dependent: :destroy
  has_many :notifications, dependent: :destroy

  # Serialization
  serialize :preferences, coder: JSON
  serialize :notification_preferences, coder: JSON

  # Validations
  validates :email, presence: true,
                   format: { with: URI::MailTo::EMAIL_REGEXP },
                   uniqueness: { case_sensitive: false }
  validates :name, presence: true, length: { minimum: 1, maximum: 100 }
  validates :status, presence: true, inclusion: { in: %w[active inactive suspended] }

  # Callbacks
  before_validation :normalize_email
  after_create :assign_default_role
  after_create :assign_permissions_after_create
  after_update :clear_reset_token_on_password_change, if: :saved_change_to_password_digest?
  before_save :set_password_changed_at, if: :password_digest_changed?
  after_touch :clear_permission_cache

  # Constants
  MAX_FAILED_ATTEMPTS = 5
  LOCKOUT_DURATION = 30.minutes
  PASSWORD_HISTORY_COUNT = 12

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :verified, -> { where.not(email_verified_at: nil) }
  scope :unverified, -> { where(email_verified_at: nil) }
  scope :locked, -> { where("locked_until > ?", Time.current) }
  scope :unlocked, -> { where("locked_until IS NULL OR locked_until <= ?", Time.current) }
  scope :with_role, ->(role_name) { joins(:roles).where(roles: { name: role_name }) }

  # JSON serialization - exclude sensitive fields
  def as_json(options = {})
    super(options.merge(except: [
      :password_digest, :failed_login_attempts, :locked_until, :password_changed_at,
      :two_factor_secret, :backup_codes
    ]))
  end

  # Instance methods
  def full_name
    name.to_s.strip
  end

  def initials
    name_parts = name.to_s.split(" ")
    return "" if name_parts.empty?

    if name_parts.length == 1
      name_parts[0][0].upcase
    else
      "#{name_parts.first[0]}#{name_parts.last[0]}".upcase
    end
  end

  def active?
    status == "active"
  end

  # NEW: Permission-based access control methods
  def has_permission?(permission_name)
    # Check if user has system.admin permission (equivalent to super admin)
    return true if roles.joins(:permissions).exists?(permissions: { name: "system.admin" })

    # Check if user has permission through any of their roles
    permissions.exists?(name: permission_name)
  end

  def has_any_permission?(*permission_names)
    permission_names.any? { |p| has_permission?(p) }
  end

  def has_all_permissions?(*permission_names)
    permission_names.all? { |p| has_permission?(p) }
  end

  def permissions
    # Users with system.admin permission have access to all permissions
    if roles.joins(:permissions).exists?(permissions: { name: "system.admin" })
      Permission.all
    else
      # Get all permissions through roles
      Permission.joins(:roles).where(roles: { id: role_ids })
    end
  end

  def permission_names
    # PERFORMANCE FIX: Cache permission names to avoid expensive queries on every token refresh
    # Cache expires after 5 minutes or when user's roles/permissions change
    cache_key = "user:#{id}:permission_names:#{updated_at.to_i}:#{role_cache_key}"

    Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      # Check if user has system.admin permission (cache this check too)
      has_system_admin = roles.joins(:permissions).exists?(permissions: { name: "system.admin" })

      if has_system_admin
        # System admins get all permissions
        Permission.pluck(:name).sort
      else
        # Regular users get permissions through their roles
        permissions.pluck(:name).uniq.sort
      end
    end
  end

  # Virtual attribute for setting permissions (useful for testing)
  # Creates or finds a role with the specified permissions and assigns it to the user
  def permissions=(permission_list)
    # Set flag to skip default role assignment (even for empty arrays)
    @permissions_explicitly_set = true
    # Store pending permissions for after_create callback
    @pending_permissions = Array(permission_list)
  end

  def assign_permissions_after_create
    # Use nil? instead of blank? to allow empty arrays (users with no permissions)
    return if @pending_permissions.nil?

    # Find or create a test role with these specific permissions
    # Use alphanumeric string that matches Role name validation
    role_name = "test_role_#{('a'..'z').to_a.sample(8).join}"
    role = Role.create!(
      name: role_name,
      display_name: "Test Role",
      role_type: "user",
      description: "Test role with custom permissions"
    )

    # Assign permissions to the role (even if empty array)
    @pending_permissions.each do |permission_name|
      permission = Permission.find_or_create_from_name!(permission_name)
      role.permissions << permission unless role.permissions.include?(permission)
    end

    # Assign role to user
    roles << role unless roles.include?(role)

    @pending_permissions = nil
    clear_permission_cache
  end

  # Cache key for role associations (changes when roles are added/removed)
  def role_cache_key
    @role_cache_key ||= role_ids.sort.join("-")
  end

  # Role checking methods
  def has_role?(role_name)
    roles.exists?(name: role_name)
  end

  def has_any_role?(*role_names)
    roles.where(name: role_names).exists?
  end

  def role_names
    roles.pluck(:name)
  end

  def add_role(role_name)
    role = Role.find_by(name: role_name)
    return false unless role

    roles << role unless roles.include?(role)
    true
  end

  # Alias for compatibility with tests
  def assign_role(role_or_name)
    if role_or_name.is_a?(Role)
      roles << role_or_name unless roles.include?(role_or_name)
    else
      add_role(role_or_name)
    end
  end

  def remove_role(role_name)
    role = Role.find_by(name: role_name)
    return false unless role

    roles.delete(role)
    true
  end

  # Convenience methods for common role checks
  def super_admin?
    has_role?("super_admin")
  end

  def admin?
    has_role?("admin") || has_role?("super_admin")
  end

  def owner?
    has_role?("owner")
  end

  def manager?
    has_role?("manager")
  end

  def member?
    has_role?("member")
  end

  def billing_admin?
    has_role?("billing_admin")
  end

  # Check if user can perform action on resource
  def can?(permission_or_action, resource = nil)
    if resource
      # Format: can?('edit', 'user') => checks 'user.edit'
      has_permission?("#{resource}.#{permission_or_action}")
    else
      # Format: can?('user.edit')
      has_permission?(permission_or_action)
    end
  end

  def cannot?(permission_or_action, resource = nil)
    !can?(permission_or_action, resource)
  end

  # Override authenticate to integrate with lockout mechanism
  def authenticate(unencrypted_password)
    if locked?
      return false
    end

    result = super(unencrypted_password)

    if result
      record_successful_login! if respond_to?(:record_successful_login!)
      result
    else
      record_failed_login! if respond_to?(:record_failed_login!) && unencrypted_password.present?
      false
    end
  end

  # Email verification
  def verified?
    email_verified_at.present?
  end

  alias_method :email_verified?, :verified?

  def verify_email!
    update!(email_verified_at: Time.current) unless verified?
  end

  def generate_email_verification_token
    self.email_verification_token = SecureRandom.urlsafe_base64
    self.email_verification_sent_at = Time.current
    save!
  end

  def email_verification_expired?
    return true unless email_verification_sent_at
    email_verification_sent_at < 24.hours.ago
  end

  # Password reset

  def create_reset_digest
    @reset_token = SecureRandom.urlsafe_base64
    update!(
      reset_digest: BCrypt::Password.create(@reset_token),
      reset_sent_at: Time.current
    )
  end

  def authenticated?(attribute, token)
    digest = send("#{attribute}_digest")
    return false if digest.nil?
    BCrypt::Password.new(digest).is_password?(token)
  end

  def reset_password!(new_password, token)
    # Verify the token matches what we stored
    return false unless reset_token_digest.present?
    return false unless BCrypt::Password.new(reset_token_digest).is_password?(token)
    return false if reset_token_expires_at && reset_token_expires_at < Time.current

    # For password reset, we need to bypass certain validations that might not apply
    # in this specific context (like password confirmation for UI forms)
    transaction do
      # Update password using update_columns to bypass model validations
      password_digest = BCrypt::Password.create(new_password)

      update_columns(
        password_digest: password_digest,
        reset_token_digest: nil,
        reset_token_expires_at: nil,
        password_changed_at: Time.current
      )

      # Create password history entry manually
      password_histories.create!(
        password_digest: password_digest,
        created_at: Time.current
      )

      # Keep only the last N passwords
      old_passwords = password_histories.order(created_at: :desc).offset(PASSWORD_HISTORY_COUNT)
      old_passwords.destroy_all if old_passwords.any?

      true
    end
  rescue => e
    Rails.logger.error "Password reset failed: #{e.message}"
    errors.add(:base, "Password reset failed: #{e.message}")
    false
  end

  def password_reset_expired?
    return true unless reset_sent_at
    reset_sent_at < 2.hours.ago
  end

  # Account locking
  def locked?
    locked_until.present? && locked_until > Time.current
  end

  def lock_account!
    update!(
      locked_until: LOCKOUT_DURATION.from_now,
      failed_login_attempts: 0
    )
  end

  def unlock_account!
    update!(
      locked_until: nil,
      failed_login_attempts: 0
    )
  end

  def increment_failed_attempts!
    self.failed_login_attempts ||= 0
    self.failed_login_attempts += 1

    if failed_login_attempts >= MAX_FAILED_ATTEMPTS
      lock_account!
    else
      save!
    end
  end

  def reset_failed_attempts!
    update!(failed_login_attempts: 0) if failed_login_attempts&.positive?
  end

  def record_login!
    update!(
      last_login_at: Time.current,
      failed_login_attempts: 0
    )
  end

  # Two-factor authentication
  def two_factor_enabled?
    two_factor_secret.present?
  end

  def enable_two_factor!(secret = nil)
    update!(
      two_factor_secret: secret || ROTP::Base32.random,
      backup_codes: generate_backup_codes
    )
  end

  def disable_two_factor!
    update!(
      two_factor_secret: nil,
      backup_codes: nil
    )
  end

  def verify_two_factor_token(token)
    return false unless two_factor_enabled?

    totp = ROTP::TOTP.new(two_factor_secret)
    totp.verify(token, drift_behind: 30, drift_ahead: 30)
  end

  def verify_backup_code(code)
    return false unless backup_codes&.include?(code)

    remaining_codes = backup_codes - [ code ]
    update!(backup_codes: remaining_codes)
    true
  end

  private

  def normalize_email
    self.email = email&.downcase&.strip
  end

  def assign_default_role
    return unless roles.empty?
    # Skip default role if permissions were explicitly set (even if empty)
    return if @permissions_explicitly_set

    # First user in account gets owner role
    if account && account.users.count == 1  # This user is the only one (just created)
      owner_role = Role.find_by(name: "owner")
      roles << owner_role if owner_role
    else
      # Assign member role by default
      member_role = Role.find_by(name: "member")
      roles << member_role if member_role
    end
  end



  def clear_reset_token_on_password_change
    update_columns(reset_token_digest: nil, reset_token_expires_at: nil) if reset_token_digest.present?
  end

  def set_password_changed_at
    self.password_changed_at = Time.current
  end

  def generate_backup_codes
    Array.new(10) { SecureRandom.hex(4).upcase }
  end

  # Clear permission cache when roles/permissions change
  def clear_permission_cache
    @role_cache_key = nil
    cache_key_pattern = "user:#{id}:permission_names:*"
    Rails.cache.delete_matched(cache_key_pattern)
  rescue => e
    Rails.logger.warn "Failed to clear permission cache for user #{id}: #{e.message}"
  end
end
