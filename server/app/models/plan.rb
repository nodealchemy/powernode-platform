class Plan < ApplicationRecord
  # Associations
  has_many :subscriptions, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true, uniqueness: { case_sensitive: false }, length: { minimum: 2, maximum: 100 }
  validates :price_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true, inclusion: { in: %w[USD EUR GBP] }
  validates :billing_cycle, presence: true, inclusion: { in: %w[monthly yearly quarterly] }
  validates :status, presence: true, inclusion: { in: %w[active inactive archived] }
  validates :trial_days, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 365 }

  # Serialization
  serialize :features, coder: JSON
  serialize :limits, coder: JSON
  serialize :default_roles, coder: JSON

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :public_plans, -> { where(public: true) }
  scope :by_billing_cycle, ->(cycle) { where(billing_cycle: cycle) }
  scope :by_currency, ->(currency) { where(currency: currency) }

  # Callbacks
  before_validation :normalize_name
  after_initialize :set_defaults

  # Instance methods
  def active?
    status == "active"
  end

  def inactive?
    status == "inactive"
  end

  def archived?
    status == "archived"
  end

  def price
    Money.new(price_cents, currency)
  rescue ArgumentError
    Money.new(price_cents, "USD")
  end

  def price=(amount)
    if amount.is_a?(Money)
      self.price_cents = amount.cents
      self.currency = amount.currency.to_s
    elsif amount.is_a?(Numeric)
      self.price_cents = (amount * 100).to_i
    end
  end

  def monthly_price
    case billing_cycle
    when "monthly"
      price
    when "quarterly"
      Money.new((price_cents / 3.0).round, currency)
    when "yearly"
      Money.new((price_cents / 12.0).round, currency)
    end
  end

  def has_feature?(feature_key)
    features.key?(feature_key.to_s) && features[feature_key.to_s]
  end

  def get_limit(limit_key)
    limits[limit_key.to_s]
  end

  def assign_default_roles_to_user(user)
    default_roles.each do |role_name|
      role = Role.find_by(name: role_name)
      user.assign_role(role) if role
    end
  end

  def can_be_deleted?
    subscriptions.active.empty?
  end

  private

  def normalize_name
    self.name = name&.strip&.titleize
  end

  def set_defaults
    self.features ||= {}
    self.limits ||= {}
    self.default_roles ||= []
  end
end
