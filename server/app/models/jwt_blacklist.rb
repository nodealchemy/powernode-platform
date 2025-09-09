# frozen_string_literal: true

# JWT Token Blacklist Model
# Stores blacklisted JWT tokens with their JTI (JWT ID) and expiration
# Used as fallback when Redis is not available

class JwtBlacklist < ApplicationRecord
  # Associations
  belongs_to :user, optional: true

  # Validations
  validates :jti, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validates :reason, length: { maximum: 100 }

  # Serialization
  serialize :metadata, coder: JSON

  # Scopes
  scope :active, -> { where('expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at <= ?', Time.current) }
  scope :user_blacklists, -> { where(user_blacklist: true) }
  scope :token_blacklists, -> { where(user_blacklist: false) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  after_create :log_creation
  before_destroy :log_destruction

  # Class methods
  def self.blacklisted?(jti)
    active.exists?(jti: jti)
  end

  def self.blacklist_user(user_id, reason: 'logout')
    create!(
      jti: "user_blacklist_#{user_id}",
      user_id: user_id,
      expires_at: 1.year.from_now,
      reason: reason,
      user_blacklist: true
    )
  rescue ActiveRecord::RecordInvalid
    # Already blacklisted
    find_by(jti: "user_blacklist_#{user_id}")
  end

  def self.cleanup_expired(batch_size: 1000)
    total_deleted = 0
    
    loop do
      deleted_count = expired.limit(batch_size).delete_all
      total_deleted += deleted_count
      
      break if deleted_count == 0
      
      # Sleep briefly to avoid overwhelming the database
      sleep(0.1) if deleted_count == batch_size
    end
    
    Rails.logger.info "Cleaned up #{total_deleted} expired JWT blacklist entries"
    total_deleted
  end

  def self.statistics
    active_count = active.count
    expired_count = expired.count
    user_blacklists = user_blacklists().count
    
    {
      total: count,
      active: active_count,
      expired: expired_count,
      user_blacklists: user_blacklists,
      token_blacklists: active_count - user_blacklists
    }
  end

  # Instance methods
  def active?
    expires_at > Time.current
  end

  def expired?
    expires_at <= Time.current
  end

  def token_blacklist?
    !user_blacklist?
  end

  def masked_jti
    return '' if jti.blank?
    # Show first 8 and last 4 characters
    if jti.length > 12
      "#{jti[0..7]}...#{jti[-4..-1]}"
    else
      jti
    end
  end

  def time_remaining
    return 0 if expired?
    (expires_at - Time.current).to_i
  end

  def expires_in_words
    return 'expired' if expired?
    
    remaining = time_remaining
    if remaining < 1.hour
      "#{remaining / 60} minutes"
    elsif remaining < 1.day
      "#{remaining / 1.hour} hours"
    else
      "#{remaining / 1.day} days"
    end
  end

  private

  def log_creation
    Rails.logger.info "JWT blacklist entry created: #{masked_jti} (#{reason})"
  end

  def log_destruction
    Rails.logger.info "JWT blacklist entry removed: #{masked_jti}"
  end
end