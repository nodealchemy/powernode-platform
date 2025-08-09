class Invitation < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :inviter, class_name: "User"
  belongs_to :role, optional: true

  # Validations
  validates :email, presence: true,
                   format: { with: URI::MailTo::EMAIL_REGEXP },
                   uniqueness: { scope: :account_id }
  validates :status, presence: true, inclusion: { in: %w[pending accepted expired cancelled] }
  validates :expires_at, presence: true

  # Callbacks
  before_validation :set_defaults, on: :create
  before_validation :normalize_email

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :accepted, -> { where(status: "accepted") }
  scope :expired, -> { where(status: "expired") }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :active, -> { where(status: "pending").where("expires_at > ?", Time.current) }

  # Instance methods
  def pending?
    status == "pending"
  end

  def accepted?
    status == "accepted"
  end

  def expired?
    status == "expired" || (pending? && expires_at < Time.current)
  end

  def cancelled?
    status == "cancelled"
  end

  def active?
    pending? && expires_at > Time.current
  end

  def expire!
    update!(status: "expired")
  end

  def cancel!
    update!(status: "cancelled")
  end

  def accept!(user)
    transaction do
      update!(
        status: "accepted",
        accepted_at: Time.current,
        accepted_by: user.id
      )

      # Assign role if specified
      user.assign_role(role) if role.present?
    end
  end

  def generate_token!
    self.token = SecureRandom.urlsafe_base64(32)
    save!
  end

  private

  def set_defaults
    self.status ||= "pending"
    self.expires_at ||= 7.days.from_now
    generate_token! if token.blank?
  end

  def normalize_email
    self.email = email&.downcase&.strip
  end
end
