# frozen_string_literal: true

module PasswordSecurity
  extend ActiveSupport::Concern

  COMMON_PASSWORDS = %w[
    password password123 123456 12345678 qwerty abc123 monkey 1234567
    letmein trustno1 dragon baseball 111111 iloveyou master sunshine
    ashley bailey passw0rd shadow 123123 654321 superman qazwsx michael
  ].freeze

  included do
    # Validations - Use PasswordStrengthService for all password validation
    validate :validate_password_strength, if: :password_required?

    # Callbacks
    before_update :track_password_change, if: :will_save_change_to_password_digest?
  end

  # Password validation using PasswordStrengthService

  def validate_password_strength
    return unless password.present?

    # Use the PasswordStrengthService for validation
    result = PasswordStrengthService.validate_password(password)

    unless result[:valid]
      result[:errors].each do |error_message|
        errors.add(:password, error_message)
      end
    end

    # Check password history (only for existing users)
    if persisted? && password_reused?
      errors.add(:password, "has been used recently. For security, please choose a different password that you haven't used in your last 12 password changes")
    end
  end

  def password_reused?
    return false unless password.present? && persisted?

    # Performance optimization: Use find_each and early termination
    password_histories
      .order(created_at: :desc)
      .limit(12)
      .find_each do |history|
        return true if BCrypt::Password.new(history.password_digest) == password
      end

    false
  end

  # Account lockout methods
  def record_failed_login!
    self.failed_login_attempts ||= 0
    self.failed_login_attempts += 1

    if failed_login_attempts >= 5
      # Exponential backoff: 30 mins, 1 hour, 2 hours, etc.
      lockout_duration = [ 30, 60, 120, 240, 480 ].min * (2 ** [ failed_login_attempts - 5, 4 ].min)
      self.locked_until = lockout_duration.minutes.from_now
    end

    save!
  end

  def record_successful_login!
    self.failed_login_attempts = 0
    self.locked_until = nil
    self.last_login_at = Time.current
    save!
  end

  def unlock!
    self.failed_login_attempts = 0
    self.locked_until = nil
    save!
  end

  # Enhanced authentication
  def authenticate_with_lockout(password)
    return false if locked?

    if authenticate(password)
      record_successful_login!
      true
    else
      record_failed_login!
      false
    end
  end

  # Password utility methods
  def password_strength
    return 0 unless password.present?
    PasswordStrengthService.score_password(password)
  end

  def password_age_days
    return nil unless password_changed_at
    ((Time.current - password_changed_at) / 1.day).to_i
  end

  def password_expired?(max_age_days = 90)
    return false unless password_changed_at
    password_age_days > max_age_days
  end

  # Password reset token methods
  def generate_reset_token!
    token = SecureRandom.urlsafe_base64(32)
    self.reset_token_digest = BCrypt::Password.create(token)
    self.reset_token_expires_at = Time.current + 1.hour
    save!
    token
  end

  def reset_token_valid?(token)
    return false if reset_token_digest.blank? || reset_token_expires_at.blank?
    return false if reset_token_expires_at < Time.current

    BCrypt::Password.new(reset_token_digest) == token
  end

  def clear_reset_token!
    self.reset_token_digest = nil
    self.reset_token_expires_at = nil
    save!
  end

  private

  def password_required?
    new_record? || password.present?
  end

  def track_password_change
    # Save current password to history before changing it
    if password_digest_was.present?
      password_histories.create!(
        password_digest: password_digest_was,
        created_at: Time.current
      )

      # Keep only last 12 password history entries
      excess_histories = password_histories.order(created_at: :desc).offset(12)
      password_histories.where(id: excess_histories.select(:id)).delete_all
    end

    self.password_changed_at = Time.current
  end
end
