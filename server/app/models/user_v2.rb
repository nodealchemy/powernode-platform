# frozen_string_literal: true

# User model with new permission system
class User < ApplicationRecord
  # Authentication
  has_secure_password

  # Attributes
  attr_reader :reset_token

  # Associations
  belongs_to :account
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :audit_logs, dependent: :nullify
  has_many :password_histories, dependent: :destroy
  has_many :pages, foreign_key: 'author_id', dependent: :destroy
  has_many :impersonation_sessions_as_impersonator, 
           class_name: 'ImpersonationSession',
           foreign_key: 'impersonator_id',
           dependent: :destroy
  has_many :impersonation_sessions_as_target,
           class_name: 'ImpersonationSession', 
           foreign_key: 'impersonated_user_id',
           dependent: :destroy

  # Serialization
  serialize :preferences, coder: JSON
  serialize :notification_preferences, coder: JSON

  # Validations
  validates :email, presence: true,
                   format: { with: URI::MailTo::EMAIL_REGEXP },
                   uniqueness: { case_sensitive: false }
  validates :first_name, presence: true, length: { minimum: 1, maximum: 50 }
  validates :last_name, presence: true, length: { minimum: 1, maximum: 50 }
  validates :status, presence: true, inclusion: { in: %w[active inactive suspended] }
  validate :password_complexity, if: :password
  validate :password_not_recently_used, if: :password

  # Callbacks
  before_validation :normalize_email
  after_create :assign_default_role
  before_update :save_password_to_history, if: :password_digest_changed?
  after_update :clear_reset_token_on_password_change, if: :saved_change_to_password_digest?
  before_save :set_password_changed_at, if: :password_digest_changed?

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
    "#{first_name} #{last_name}".strip
  end

  def initials
    "#{first_name[0]}#{last_name[0]}".upcase
  end

  def active?
    status == "active"
  end

  # NEW: Permission-based access control methods
  def has_permission?(permission_name)
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
    # Get all permissions through roles
    Permission.joins(:roles).where(roles: { id: role_ids })
  end

  def permission_names
    permissions.pluck(:name).uniq.sort
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

  def remove_role(role_name)
    role = Role.find_by(name: role_name)
    return false unless role
    
    roles.delete(role)
    true
  end

  # Convenience methods for common role checks
  def super_admin?
    has_role?('super_admin')
  end

  def admin?
    has_role?('admin') || super_admin?
  end

  def owner?
    has_role?('owner')
  end

  def manager?
    has_role?('manager')
  end

  def member?
    has_role?('member')
  end

  def billing_admin?
    has_role?('billing_admin')
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

  # Email verification
  def verified?
    email_verified_at.present?
  end

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
    
    remaining_codes = backup_codes - [code]
    update!(backup_codes: remaining_codes)
    true
  end

  private

  def normalize_email
    self.email = email&.downcase&.strip
  end

  def assign_default_role
    # Assign member role by default
    member_role = Role.find_by(name: 'member')
    roles << member_role if member_role && roles.empty?
  end

  def password_complexity
    return unless password.present?

    unless password.match?(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/)
      errors.add(:password, 'must include at least one lowercase letter, one uppercase letter, one digit, and one special character')
    end

    if password.length < 12
      errors.add(:password, 'must be at least 12 characters long')
    end
  end

  def password_not_recently_used
    return unless password.present? && id.present?

    recent_passwords = password_histories.order(created_at: :desc).limit(PASSWORD_HISTORY_COUNT)
    
    recent_passwords.each do |history|
      if BCrypt::Password.new(history.password_digest).is_password?(password)
        errors.add(:password, "has been used recently. Please choose a different password.")
        break
      end
    end
  end

  def save_password_to_history
    return unless password_digest.present?
    
    password_histories.create!(password_digest: password_digest)
    
    # Keep only the last N passwords
    old_passwords = password_histories.order(created_at: :desc).offset(PASSWORD_HISTORY_COUNT)
    old_passwords.destroy_all if old_passwords.any?
  end

  def clear_reset_token_on_password_change
    update_columns(reset_digest: nil, reset_sent_at: nil) if reset_digest.present?
  end

  def set_password_changed_at
    self.password_changed_at = Time.current
  end

  def generate_backup_codes
    Array.new(10) { SecureRandom.hex(4).upcase }
  end
end