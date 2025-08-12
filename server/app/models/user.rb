class User < ApplicationRecord
  # Authentication
  has_secure_password

  # Attributes
  attr_reader :reset_token

  # Associations
  belongs_to :account
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
  validates :role, presence: true, inclusion: { in: %w[admin owner member] }
  validate :password_complexity, if: :password
  validate :password_not_recently_used, if: :password

  # Callbacks
  before_validation :normalize_email
  before_create :set_owner_if_first_user
  after_create :assign_owner_role_if_needed
  before_update :save_password_to_history, if: :password_digest_changed?
  after_update :clear_reset_token_on_password_change, if: :saved_change_to_password_digest?
  before_save :set_password_changed_at, if: :password_digest_changed?

  # Constants
  MAX_FAILED_ATTEMPTS = 5
  LOCKOUT_DURATION = 30.minutes
  PASSWORD_HISTORY_COUNT = 12

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :owners, -> { where(role: "owner") }
  scope :admins, -> { where(role: "admin") }
  scope :members, -> { where(role: "member") }
  scope :verified, -> { where.not(email_verified_at: nil) }
  scope :unverified, -> { where(email_verified_at: nil) }
  scope :locked, -> { where("locked_until > ?", Time.current) }
  scope :unlocked, -> { where("locked_until IS NULL OR locked_until <= ?", Time.current) }

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

  def owner?
    role == 'owner'
  end

  def admin?
    role == 'admin'
  end

  def member?
    role == 'member'
  end
  
  def admin_or_owner?
    admin? || owner?
  end

  def email_verified?
    email_verified_at.present?
  end

  def verify_email!
    update!(email_verified_at: Time.current)
  end

  def record_login!
    update!(last_login_at: Time.current)
  end

  def has_role?(role_name)
    role == role_name.downcase
  end

  def has_permission?(permission_name)
    # For single role system, check permissions through role
    return false unless role.present?
    
    role_record = Role.find_by(name: role.titleize)
    role_record&.has_permission?(permission_name) || false
  end

  def assign_role(new_role)
    self.role = new_role.is_a?(String) ? new_role.downcase : new_role.name.downcase
    save! if persisted?
  end

  def all_permissions
    return Permission.none unless role.present?
    
    role_record = Role.find_by(name: role.titleize)
    role_record&.permissions || Permission.none
  end

  # Password security methods
  def locked?
    locked_until.present? && locked_until > Time.current
  end

  def unlock!
    update!(
      failed_login_attempts: 0,
      locked_until: nil
    )
  end

  def record_failed_login!
    increment!(:failed_login_attempts)

    if failed_login_attempts >= MAX_FAILED_ATTEMPTS
      lock_account!
    end
  end

  def record_successful_login!
    update!(
      failed_login_attempts: 0,
      locked_until: nil,
      last_login_at: Time.current
    )
  end

  def password_strength
    return nil unless password_digest.present?

    # We can't get the original password from digest, so this is for new passwords only
    @password_strength ||= PasswordStrengthService.score_password(@password || "")
  end

  def password_age_days
    return nil unless password_changed_at.present?

    ((Time.current - password_changed_at) / 1.day).round
  end

  def password_expired?(max_age_days = 90)
    return false unless password_changed_at.present?

    password_age_days > max_age_days
  end

  # Password reset methods
  def generate_reset_token!
    payload = {
      user_id: id,
      type: "password_reset",
      exp: 1.hour.from_now.to_i
    }
    jwt_token = JWT.encode(payload, Rails.application.config.jwt_secret_key, "HS256")

    self.reset_token_digest = BCrypt::Password.create(jwt_token)
    self.reset_token_expires_at = 1.hour.from_now
    @reset_token = jwt_token
    save!
    jwt_token
  end

  def reset_token_valid?(token)
    return false unless token.present? && reset_token_digest.present?
    return false if reset_token_expires_at.present? && Time.current > reset_token_expires_at

    begin
      payload = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: "HS256").first
      BCrypt::Password.new(reset_token_digest) == token && 
      payload["user_id"] == id && 
      payload["type"] == "password_reset" && 
      Time.current < Time.at(payload["exp"])
    rescue JWT::DecodeError, JWT::ExpiredSignature
      false
    end
  end

  def reset_password!(new_password, token)
    return false unless reset_token_valid?(token)

    self.password = new_password
    self.password_confirmation = new_password
    self.reset_token_digest = nil
    self.reset_token_expires_at = nil
    save!
  end

  def clear_reset_token!
    update!(reset_token_digest: nil, reset_token_expires_at: nil)
  end

  # Analytics permission helper methods
  def can?(permission_action)
    case permission_action.to_s
    when "view_analytics"
      has_permission?("analytics.read") || owner? || admin?
    when "export_analytics"
      has_permission?("analytics.export") || owner? || admin?
    when "view_global_analytics"
      has_permission?("analytics.global") || owner?
    else
      false
    end
  end

  # Two-Factor Authentication methods
  def two_factor_enabled?
    two_factor_enabled && two_factor_secret.present?
  end

  def enable_two_factor!
    self.two_factor_secret = ROTP::Base32.random
    self.two_factor_enabled = true
    self.two_factor_enabled_at = Time.current
    self.backup_codes = generate_backup_codes
    self.two_factor_backup_codes_generated_at = Time.current
    save!

    # Create audit log entry
    AuditLog.create!(
      user: self,
      account: account,
      action: "two_factor_enabled",
      resource_type: "User",
      resource_id: id,
      source: "api",
      metadata: { method: "totp" }
    )

    two_factor_secret
  end

  def disable_two_factor!
    self.two_factor_enabled = false
    self.two_factor_secret = nil
    self.backup_codes = nil
    self.two_factor_enabled_at = nil
    self.two_factor_backup_codes_generated_at = nil
    save!

    # Create audit log entry
    AuditLog.create!(
      user: self,
      account: account,
      action: "two_factor_disabled",
      resource_type: "User",
      resource_id: id,
      source: "api"
    )
  end

  def verify_two_factor_token(token)
    return false unless two_factor_enabled?
    return false unless token.present?

    # Remove spaces and ensure 6 digits
    clean_token = token.to_s.gsub(/\s+/, "")
    return false unless clean_token.match(/\A\d{6}\z/)

    # Check TOTP token
    totp = ROTP::TOTP.new(two_factor_secret, issuer: "Powernode")
    return true if totp.verify(clean_token, drift_behind: 30, drift_ahead: 30)

    # Check backup codes if TOTP fails
    verify_backup_code(clean_token)
  end

  def verify_backup_code(code)
    return false unless backup_codes.present?
    return false unless code.present?

    codes_array = JSON.parse(backup_codes)
    code_index = codes_array.find_index(code.to_s)

    if code_index
      # Remove the used backup code
      codes_array.delete_at(code_index)
      self.backup_codes = codes_array.to_json
      save!

      # Create audit log entry for backup code usage
      AuditLog.create!(
        user: self,
        account: account,
        action: "two_factor_backup_code_used",
        resource_type: "User",
        resource_id: id,
        source: "api",
        metadata: { remaining_codes: codes_array.size }
      )

      return true
    end

    false
  end

  def two_factor_qr_code
    return nil unless two_factor_secret.present?

    totp = ROTP::TOTP.new(two_factor_secret, issuer: "Powernode")
    provisioning_uri = totp.provisioning_uri("#{email} (#{account.name})")
    
    qrcode = RQRCode::QRCode.new(provisioning_uri)
    qrcode.as_svg(
      offset: 0,
      color: '000',
      shape_rendering: 'crispEdges',
      module_size: 6,
      standalone: true
    )
  end

  def two_factor_backup_codes
    return [] unless backup_codes.present?
    JSON.parse(backup_codes)
  end

  def regenerate_backup_codes!
    self.backup_codes = generate_backup_codes
    self.two_factor_backup_codes_generated_at = Time.current
    save!

    # Create audit log entry
    AuditLog.create!(
      user: self,
      account: account,
      action: "two_factor_backup_codes_regenerated",
      resource_type: "User",
      resource_id: id,
      source: "api"
    )

    two_factor_backup_codes
  end

  def two_factor_provisioning_uri
    return nil unless two_factor_secret.present?

    totp = ROTP::TOTP.new(two_factor_secret, issuer: "Powernode")
    totp.provisioning_uri("#{email} (#{account.name})")
  end

  # Override authenticate method to handle account lockout
  def authenticate(unencrypted_password)
    return false if locked?

    result = super(unencrypted_password)

    if result
      record_successful_login!
    else
      record_failed_login!
    end

    result
  end

  private

  def normalize_email
    self.email = email&.downcase&.strip
  end

  def set_owner_if_first_user
    # Only assign Owner role if this is the first user in the account
    if account&.users&.count&.zero?
      # This will be handled in after_create callback to assign Owner role
      @should_be_owner = true
    end
  end

  def assign_owner_role_if_needed
    if @should_be_owner
      # For single role system, just set the role column
      self.role = 'owner'
      save! if persisted?
    end
  end

  def password_complexity
    return unless password.present?

    result = PasswordStrengthService.validate_password(password)

    unless result[:valid]
      result[:errors].each { |error| errors.add(:password, error) }
    end
  end

  def password_not_recently_used
    return unless password.present? && persisted?

    if PasswordHistory.password_recently_used?(self, password)
      errors.add(:password, "cannot be the same as any of your last #{PASSWORD_HISTORY_COUNT} passwords")
    end
  end

  def save_password_to_history
    # Save the OLD password digest before it changes
    old_digest = password_digest_was
    if old_digest.present?
      PasswordHistory.add_for_user(self, old_digest)
      PasswordHistory.cleanup_old_entries(self, PASSWORD_HISTORY_COUNT)
    end
  end

  def set_password_changed_at
    self.password_changed_at = Time.current
  end

  def clear_reset_token_on_password_change
    # Clear reset token when password changes to prevent replay attacks
    self.reset_token_digest = nil
    self.reset_token_expires_at = nil
  end

  def lock_account!
    # Exponential backoff: base duration * (2 ^ (attempts - max_attempts))
    multiplier = 2 ** [ (failed_login_attempts - MAX_FAILED_ATTEMPTS), 5 ].min
    lockout_duration = LOCKOUT_DURATION * multiplier

    update!(
      locked_until: Time.current + lockout_duration
    )
  end

  def generate_backup_codes
    codes = []
    10.times do
      codes << SecureRandom.random_number(100_000_000).to_s.rjust(8, '0')
    end
    codes.to_json
  end
end
