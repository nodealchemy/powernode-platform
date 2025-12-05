# frozen_string_literal: true

class Invitation < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :inviter, class_name: 'User', foreign_key: 'inviter_id'

  # Validations
  validates :email, presence: true, 
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { scope: :account_id, message: "has already been invited to this account" }
  validates :status, presence: true, inclusion: { in: %w[pending accepted expired cancelled] }
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validates :first_name, presence: true
  validates :last_name, presence: true
  validate :validate_role_names
  validate :inviter_can_send_invitations

  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :expired, -> { where('expires_at < ?', Time.current) }
  scope :active, -> { pending.where('expires_at >= ?', Time.current) }

  # Callbacks
  before_validation :generate_token, on: :create
  before_validation :set_expiration, on: :create
  before_validation :generate_token_digest, on: :create
  before_create :set_defaults

  # State management
  def accept!
    return false if expired? || !pending?
    
    transaction do
      update!(status: 'accepted', accepted_at: Time.current)
      # User creation would happen in the controller
    end
  end

  def cancel!
    return false if expired? || !pending?
    update!(status: 'cancelled')
  end

  def expired?
    expires_at && expires_at < Time.current
  end

  def pending?
    status == 'pending'
  end

  def accepted?
    status == 'accepted'
  end

  def cancelled?
    status == 'cancelled'
  end

  # Class method to find invitation by token
  def self.find_by_token(token)
    return nil if token.blank?

    digest = Digest::SHA256.hexdigest(token)
    where(token_digest: digest).first
  end

  # Instance method to verify token
  def valid_token?(token)
    return false if token.blank?

    Digest::SHA256.hexdigest(token) == token_digest
  end

  # Helper methods for role management
  def add_role(role_name)
    self.role_names ||= []
    self.role_names << role_name unless self.role_names.include?(role_name)
    self.role_names.uniq!
  end

  def remove_role(role_name)
    self.role_names ||= []
    self.role_names.delete(role_name)
  end

  def has_role?(role_name)
    role_names&.include?(role_name) || false
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32) if token.blank?
  end

  def generate_token_digest
    self.token_digest = Digest::SHA256.hexdigest(token) if token.present? && token_digest.blank?
  end

  def set_expiration
    self.expires_at = 7.days.from_now if expires_at.blank?
  end

  def set_defaults
    self.status = 'pending' if status.blank?
    self.role_names ||= ['member'] # Default to member role if not specified
  end

  def validate_role_names
    return if role_names.blank?
    
    unless role_names.is_a?(Array)
      errors.add(:role_names, "must be an array")
      return
    end
    
    invalid_roles = role_names - Role.pluck(:name)
    if invalid_roles.any?
      errors.add(:role_names, "contains invalid roles: #{invalid_roles.join(', ')}")
    end
  end

  def inviter_can_send_invitations
    return if inviter.blank?
    
    unless inviter.has_permission?('team.invite') || inviter.has_permission?('users.create')
      errors.add(:inviter, "does not have permission to send invitations")
    end
  end
end