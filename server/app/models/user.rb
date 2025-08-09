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
  before_create :set_owner_if_first_user
  after_create :assign_owner_role_if_needed
  after_update :save_password_to_history, if: :saved_change_to_password_digest?
  before_save :set_password_changed_at, if: :password_digest_changed?

  # Constants
  MAX_FAILED_ATTEMPTS = 5
  LOCKOUT_DURATION = 30.minutes
  PASSWORD_HISTORY_COUNT = 12

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :owners, -> { joins(:roles).where(roles: { name: "Owner" }) }
  scope :admins, -> { joins(:roles).where(roles: { name: "Admin" }) }
  scope :members, -> { joins(:roles).where(roles: { name: "Member" }) }
  scope :verified, -> { where.not(email_verified_at: nil) }
  scope :unverified, -> { where(email_verified_at: nil) }
  scope :locked, -> { where("locked_until > ?", Time.current) }
  scope :unlocked, -> { where("locked_until IS NULL OR locked_until <= ?", Time.current) }

  # JSON serialization - exclude sensitive fields
  def as_json(options = {})
    super(options.merge(except: [ :password_digest, :failed_login_attempts, :locked_until, :password_changed_at ]))
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
    roles.exists?(name: 'Owner')
  end

  def admin?
    roles.exists?(name: 'Admin')
  end

  def member?
    roles.exists?(name: 'Member')
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
    roles.exists?(name: role_name)
  end

  def has_permission?(permission_name)
    roles.joins(:permissions).exists?(permissions: { name: permission_name })
  end

  def assign_role(role)
    roles << role unless has_role?(role.name)
  end

  def remove_role(role)
    roles.delete(role)
  end

  def all_permissions
    Permission.joins(:roles).where(roles: { id: role_ids })
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
      owner_role = Role.find_or_create_by!(name: 'Owner') do |role|
        role.description = 'Account owner with full administrative access'
        role.system_role = true
      end
      roles << owner_role unless roles.exists?(name: 'Owner')
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
    PasswordHistory.add_for_user(self, password_digest)
    PasswordHistory.cleanup_old_entries(self, PASSWORD_HISTORY_COUNT)
  end

  def set_password_changed_at
    self.password_changed_at = Time.current
  end

  def lock_account!
    # Exponential backoff: base duration * (2 ^ (attempts - max_attempts))
    multiplier = 2 ** [ (failed_login_attempts - MAX_FAILED_ATTEMPTS), 5 ].min
    lockout_duration = LOCKOUT_DURATION * multiplier

    update!(
      locked_until: Time.current + lockout_duration
    )
  end
end
