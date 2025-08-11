class AccountDelegation < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :delegated_user, class_name: 'User', foreign_key: 'delegated_user_id'
  belongs_to :delegated_by, class_name: 'User', foreign_key: 'delegated_by_id'
  belongs_to :revoked_by, class_name: 'User', foreign_key: 'revoked_by', optional: true
  belongs_to :role, optional: true

  # Validations
  validates :delegated_by_id, uniqueness: { scope: [:account_id, :delegated_user_id], 
                                           message: "has already delegated to this user for this account" }
  validates :status, presence: true, inclusion: { in: %w[active inactive revoked] }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :for_account, ->(account) { where(account: account) }
  scope :for_user, ->(user) { where(delegated_user: user) }
  scope :not_expired, -> { where('expires_at IS NULL OR expires_at >= ?', Time.current) }

  # Callbacks
  before_create :set_defaults

  # State management
  def active?
    status == 'active' && !expired?
  end

  def inactive?
    status == 'inactive'
  end

  def revoked?
    status == 'revoked'
  end

  def expired?
    expires_at && expires_at < Time.current
  end

  def activate!
    update!(status: 'active')
  end

  def deactivate!
    update!(status: 'inactive')
  end

  def revoke!(revoked_by_user)
    update!(status: 'revoked', revoked_at: Time.current, revoked_by: revoked_by_user)
  end

  private

  def set_defaults
    self.status = 'active' if status.blank?
  end
end