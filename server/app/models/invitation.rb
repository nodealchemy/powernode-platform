class Invitation < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :inviter, class_name: 'User', foreign_key: 'inviter_id'

  # Validations
  validates :email, presence: true, 
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { scope: :account_id, message: "has already been invited to this account" }
  validates :status, presence: true, inclusion: { in: %w[pending accepted rejected expired] }
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :role, presence: true, inclusion: { in: %w[admin owner member], message: "must be admin, owner, or member" }
  validate :inviter_can_send_invitations

  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :expired, -> { where('expires_at < ?', Time.current) }
  scope :active, -> { pending.where('expires_at >= ?', Time.current) }

  # Callbacks
  before_validation :generate_token, on: :create
  before_validation :set_expiration, on: :create
  before_create :set_defaults

  # State management
  def accept!
    return false if expired? || !pending?
    
    transaction do
      update!(status: 'accepted', accepted_at: Time.current)
      # User creation would happen in the controller
    end
  end

  def revoke!
    return false if expired? || !pending?
    update!(status: 'revoked', revoked_at: Time.current)
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

  def revoked?
    status == 'revoked'
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32) if token.blank?
  end

  def set_expiration
    self.expires_at = 7.days.from_now if expires_at.blank?
  end

  def set_defaults
    self.status = 'pending' if status.blank?
    self.role = 'member' if role.blank? # Default to member role if not specified
  end

  def inviter_can_send_invitations
    return if inviter.blank?
    
    unless inviter.admin_or_owner?
      errors.add(:inviter, "must be an admin or owner to send invitations")
    end
  end
end