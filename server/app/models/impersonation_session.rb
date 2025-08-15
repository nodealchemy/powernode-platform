# frozen_string_literal: true

class ImpersonationSession < ApplicationRecord
  belongs_to :impersonator, class_name: 'User'
  belongs_to :impersonated_user, class_name: 'User'
  belongs_to :account, required: true

  validates :session_token, presence: true, uniqueness: true
  validates :reason, length: { maximum: 500 }, allow_blank: true
  validates :ip_address, length: { maximum: 45 }, allow_blank: true
  validates :user_agent, length: { maximum: 500 }, allow_blank: true
  validates :started_at, presence: true
  validate :same_account_validation
  validate :prevent_self_impersonation

  scope :active, -> { where(active: true) }
  scope :ended, -> { where(active: false) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :by_impersonator, ->(user_id) { where(impersonator_id: user_id) }
  scope :recent, -> { order(started_at: :desc) }

  before_validation :set_started_at, on: :create
  before_validation :generate_session_token, on: :create
  before_validation :set_account_from_users, on: :create

  # Maximum impersonation session duration (8 hours)
  MAX_SESSION_DURATION = 8.hours

  def active?
    active && !expired?
  end

  def expired?
    return false unless started_at
    
    Time.current > (started_at + MAX_SESSION_DURATION)
  end

  def duration
    return nil unless started_at
    
    end_time = ended_at || Time.current
    end_time - started_at
  end

  def end_session!
    update!(
      active: false,
      ended_at: Time.current
    )
  end

  def self.cleanup_expired_sessions
    expired_sessions = active.where('started_at < ?', MAX_SESSION_DURATION.ago)
    count = expired_sessions.count
    
    expired_sessions.update_all(
      active: false,
      ended_at: Time.current
    )
    
    count
  end

  def self.active_session_for_user(user_id)
    active.find_by(impersonated_user_id: user_id)
  end

  def self.create_session!(impersonator:, impersonated_user:, reason: nil, ip_address: nil, user_agent: nil)
    # End any existing active sessions for this user
    active.where(impersonated_user: impersonated_user).update_all(
      active: false,
      ended_at: Time.current
    )

    create!(
      impersonator: impersonator,
      impersonated_user: impersonated_user,
      account: impersonated_user.account,
      reason: reason,
      ip_address: ip_address,
      user_agent: user_agent
    )
  end

  private

  def set_started_at
    self.started_at ||= Time.current
  end

  def generate_session_token
    self.session_token = SecureRandom.hex(32) if session_token.blank?
  end

  def set_account_from_users
    return unless impersonated_user
    
    self.account = impersonated_user.account
  end

  def same_account_validation
    return unless impersonator && impersonated_user
    
    # System administrators can impersonate users from any account
    unless impersonator.admin? || impersonator.account == impersonated_user.account
      errors.add(:base, 'Impersonator and impersonated user must be in the same account')
    end
  end

  def prevent_self_impersonation
    return unless impersonator && impersonated_user
    
    if impersonator == impersonated_user
      errors.add(:base, 'Cannot impersonate yourself')
    end
  end
end