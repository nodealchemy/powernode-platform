class Account < ApplicationRecord
  # Associations
  has_many :users, dependent: :destroy
  has_one :subscription, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :account_delegations, dependent: :destroy
  has_many :audit_logs, dependent: :destroy
  has_many :payment_methods, dependent: :destroy
  has_many :webhook_events, dependent: :destroy
  has_many :revenue_snapshots, dependent: :destroy

  # Subscription-related associations
  has_many :invoices, through: :subscription
  has_many :payments, through: :invoices

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :subdomain, format: { with: /\A[a-z0-9\-]+\z/, message: "can only contain lowercase letters, numbers, and hyphens" },
                       length: { minimum: 3, maximum: 30 },
                       uniqueness: { case_sensitive: false },
                       allow_blank: true
  validates :status, presence: true, inclusion: { in: %w[active suspended cancelled] }

  # Serialization
  serialize :settings, coder: JSON

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :suspended, -> { where(status: "suspended") }
  scope :cancelled, -> { where(status: "cancelled") }

  # Callbacks
  before_validation :normalize_subdomain
  after_initialize :set_defaults

  # Instance methods
  def active?
    status == "active"
  end

  def suspended?
    status == "suspended"
  end

  def cancelled?
    status == "cancelled"
  end

  def owner
    users.joins(:user_roles).joins("JOIN roles ON user_roles.role_id = roles.id")
         .where(roles: { name: "Owner" }).first
  end

  def current_subscription
    subscription
  end

  def has_active_subscription?
    subscription&.active? || false
  end

  def subscription_status
    subscription&.status || "none"
  end

  def on_trial?
    subscription&.on_trial? || false
  end

  private

  def normalize_subdomain
    self.subdomain = subdomain&.downcase&.strip
  end

  def set_defaults
    self.settings ||= {}
  end
end
