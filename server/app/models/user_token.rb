# frozen_string_literal: true

class UserToken < ApplicationRecord
  belongs_to :user
  
  # Token types
  TOKEN_TYPES = %w[access refresh api_key 2fa impersonation].freeze
  
  # Default expiration times
  EXPIRATION_TIMES = {
    access: 24.hours,
    refresh: 30.days,
    api_key: 1.year,
    '2fa' => 10.minutes,
    impersonation: 8.hours
  }.freeze

  # Validations
  validates :token_digest, presence: true, uniqueness: true
  validates :token_type, presence: true, inclusion: { in: TOKEN_TYPES }
  validates :expires_at, presence: true
  validates :name, length: { maximum: 100 }
  validates :scopes, length: { maximum: 500 }
  
  # Serialization
  serialize :permissions, coder: JSON

  # Scopes
  scope :active, -> { where(revoked: false).where('expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at <= ?', Time.current) }
  scope :revoked, -> { where(revoked: true) }
  scope :by_type, ->(type) { where(token_type: type) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :set_default_expiration, if: :new_record?
  after_create :cleanup_expired_tokens
  
  # Class methods
  def self.generate_token
    SecureRandom.urlsafe_base64(48)
  end
  
  def self.create_token_for_user(user, type: 'access', name: nil, scopes: nil, expires_in: nil, permissions: nil)
    token = generate_token
    token_digest = Digest::SHA256.hexdigest(token)
    
    expires_at = expires_in ? expires_in.from_now : EXPIRATION_TIMES[type.to_sym].from_now
    
    # Cache user permissions for faster lookup
    cached_permissions = permissions || user.permission_names
    
    user_token = create!(
      user: user,
      token_digest: token_digest,
      token_type: type,
      name: name,
      permissions: cached_permissions,
      scopes: scopes,
      expires_at: expires_at
    )
    
    # Return both the token and the record
    { token: token, user_token: user_token }
  end
  
  def self.find_by_token(token)
    return nil if token.blank?
    
    token_digest = Digest::SHA256.hexdigest(token)
    active.find_by(token_digest: token_digest)
  end
  
  def self.authenticate(token)
    user_token = find_by_token(token)
    return nil unless user_token
    
    # Update last used information
    user_token.touch_last_used!
    
    user_token
  end
  
  def self.cleanup_expired
    expired.delete_all
    revoked.where('revoked_at < ?', 7.days.ago).delete_all
  end

  # Instance methods
  def active?
    !revoked? && !expired?
  end
  
  def expired?
    expires_at <= Time.current
  end
  
  def revoke!(reason: 'manual')
    update!(
      revoked: true,
      revoked_at: Time.current,
      revoked_reason: reason
    )
  end
  
  def touch_last_used!(ip: nil, user_agent: nil)
    update_columns(
      last_used_at: Time.current,
      last_used_ip: ip,
      user_agent: user_agent&.truncate(500)
    )
  end
  
  def refresh!
    return nil unless token_type == 'refresh' && active?
    
    # Generate new access token
    UserToken.create_token_for_user(
      user, 
      type: 'access',
      permissions: permissions
    )
  end
  
  def scope_list
    return [] if scopes.blank?
    scopes.split(',').map(&:strip)
  end
  
  def has_scope?(scope)
    scope_list.include?(scope.to_s)
  end
  
  def has_permission?(permission_name)
    # Users with system.admin permission have all permissions
    return true if permissions&.include?('system.admin')

    # Check cached permissions first (faster)
    return permissions&.include?(permission_name) if permissions.present?

    # Fallback to user permissions
    user.has_permission?(permission_name)
  end
  
  def display_name
    name.present? ? name : "#{token_type.humanize} Token"
  end
  
  def masked_token
    return nil unless token_digest.present?
    
    # Show first 8 and last 4 characters of digest
    digest_preview = token_digest[0..7] + '...' + token_digest[-4..-1]
    "tok_#{digest_preview}"
  end

  private
  
  def set_default_expiration
    return if expires_at.present?
    
    self.expires_at = EXPIRATION_TIMES[token_type.to_sym]&.from_now || 24.hours.from_now
  end
  
  def cleanup_expired_tokens
    # Clean up expired tokens for this user periodically
    return unless rand < 0.1 # 10% chance to run cleanup
    
    self.class.where(user: user).expired.limit(100).delete_all
  end
end