class AccountDelegation < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :delegated_user, class_name: "User"
  belongs_to :delegated_by, class_name: "User"
  belongs_to :role, optional: true

  # Validations
  validates :delegated_user_id, presence: true, uniqueness: { scope: :account_id }
  validates :status, presence: true, inclusion: { in: %w[active inactive revoked] }
  validates :expires_at, presence: true

  # Callbacks
  before_validation :set_defaults, on: :create

  # Scopes
  scope :active, -> { where(status: "active").where("expires_at > ?", Time.current) }
  scope :inactive, -> { where(status: "inactive") }
  scope :revoked, -> { where(status: "revoked") }
  scope :expired, -> { where("expires_at <= ?", Time.current) }

  # Instance methods
  def active?
    status == "active" && expires_at > Time.current
  end

  def inactive?
    status == "inactive"
  end

  def revoked?
    status == "revoked"
  end

  def expired?
    expires_at <= Time.current
  end

  def revoke!(revoked_by_user)
    update!(
      status: "revoked",
      revoked_at: Time.current,
      revoked_by: revoked_by_user.id
    )
  end

  def activate!
    update!(status: "active")
  end

  def deactivate!
    update!(status: "inactive")
  end

  private

  def set_defaults
    self.status ||= "active"
    self.expires_at ||= 1.year.from_now
  end
end
