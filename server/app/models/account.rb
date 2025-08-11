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
  has_many :services, dependent: :destroy

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
  after_create :broadcast_customer_created
  after_update :broadcast_customer_updated, if: :saved_changes?

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
    users.where(role: "owner").first
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

  def broadcast_customer_created
    broadcast_customer_change('created')
  end

  def broadcast_customer_updated
    broadcast_customer_change('updated')
  end

  def broadcast_customer_change(event_type)
    # Broadcast to all admin users
    data = {
      type: 'customer_updated',
      event: event_type,
      customer_id: id,
      timestamp: Time.current.iso8601
    }
    
    # Find all admin accounts that should receive this update
    admin_accounts = Account.joins(:users).where(users: { role: ['owner', 'admin'] }).distinct
    
    admin_accounts.each do |admin_account|
      ActionCable.server.broadcast("customer_updates_#{admin_account.id}", data)
    end
  rescue => e
    Rails.logger.error "Failed to broadcast customer change: #{e.message}"
  end
end
