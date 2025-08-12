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
  validates :annual_discount_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :promotional_discount_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :promotional_discount_code, uniqueness: { case_sensitive: false }, allow_blank: true
  validate :validate_promotional_discount_dates
  validate :validate_volume_discount_tiers

  # Note: features, limits, default_roles, volume_discount_tiers are now native JSON columns
  # No explicit serialization needed in Rails 8

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :public_plans, -> { where(is_public: true) }
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

  # Discount calculation methods
  def calculate_discounted_price(billing_cycle: self.billing_cycle, quantity: 1, promo_code: nil)
    base_price = price_cents
    
    # Apply annual discount if requesting yearly billing
    if has_annual_discount? && billing_cycle == 'yearly' && self.billing_cycle == 'monthly'
      base_price = (base_price * 12 * (1 - annual_discount_percent / 100.0)).round
    end
    
    # Apply volume discount if applicable
    if has_volume_discount? && quantity > 1
      volume_discount = calculate_volume_discount(quantity)
      base_price = (base_price * (1 - volume_discount / 100.0)).round
    end
    
    # Apply promotional discount if valid
    if has_promotional_discount? && valid_promotional_discount?(promo_code)
      base_price = (base_price * (1 - promotional_discount_percent / 100.0)).round
    end
    
    Money.new(base_price * quantity, currency)
  end

  def calculate_volume_discount(quantity)
    return 0.0 unless has_volume_discount? && volume_discount_tiers.is_a?(Array)
    
    applicable_tier = volume_discount_tiers
      .select { |tier| quantity >= tier['min_quantity'] }
      .max_by { |tier| tier['min_quantity'] }
    
    applicable_tier ? applicable_tier['discount_percent'].to_f : 0.0
  end

  def valid_promotional_discount?(promo_code = nil)
    return false unless has_promotional_discount?
    return false if promotional_discount_start && promotional_discount_start > Time.current
    return false if promotional_discount_end && promotional_discount_end < Time.current
    return false if promotional_discount_code.present? && promotional_discount_code != promo_code
    
    true
  end

  def annual_savings_amount
    return Money.new(0, currency) unless has_annual_discount? && billing_cycle == 'monthly'
    
    monthly_total = price_cents * 12
    yearly_discounted = (monthly_total * (1 - annual_discount_percent / 100.0)).round
    
    Money.new(monthly_total - yearly_discounted, currency)
  end

  def annual_savings_percentage
    has_annual_discount? ? annual_discount_percent : 0.0
  end

  private

  def normalize_name
    self.name = name&.strip&.titleize
  end

  def set_defaults
    self.features ||= {}
    self.limits ||= {}
    self.default_roles ||= []
    self.volume_discount_tiers ||= []
  end

  def validate_promotional_discount_dates
    return unless has_promotional_discount?
    
    if promotional_discount_start && promotional_discount_end && promotional_discount_start >= promotional_discount_end
      errors.add(:promotional_discount_end, "must be after start date")
    end
  end

  def validate_volume_discount_tiers
    return unless has_volume_discount? && volume_discount_tiers.present?
    
    unless volume_discount_tiers.is_a?(Array)
      errors.add(:volume_discount_tiers, "must be an array")
      return
    end
    
    volume_discount_tiers.each_with_index do |tier, index|
      unless tier.is_a?(Hash) && tier['min_quantity'].present? && tier['discount_percent'].present?
        errors.add(:volume_discount_tiers, "tier #{index + 1} must have min_quantity and discount_percent")
      end
      
      if tier['min_quantity'].to_i <= 0
        errors.add(:volume_discount_tiers, "tier #{index + 1} min_quantity must be greater than 0")
      end
      
      if tier['discount_percent'].to_f < 0 || tier['discount_percent'].to_f > 100
        errors.add(:volume_discount_tiers, "tier #{index + 1} discount_percent must be between 0 and 100")
      end
    end
  end
end
