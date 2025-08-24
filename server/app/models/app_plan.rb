# frozen_string_literal: true

class AppPlan < ApplicationRecord
  include AuditLogging
  
  # Associations
  belongs_to :app
  has_many :app_subscriptions, dependent: :destroy
  has_many :subscribers, through: :app_subscriptions, source: :account
  
  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 255 }
  validates :slug, presence: true, uniqueness: { scope: :app_id }
  validates :price_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :billing_interval, presence: true, inclusion: { in: %w[monthly yearly one_time] }
  validates :description, length: { maximum: 1000 }
  
  # JSON validations
  validates :features, presence: true
  validates :permissions, presence: true
  validates :limits, presence: true
  validates :metadata, presence: true
  
  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :public_plans, -> { where(is_public: true) }
  scope :private_plans, -> { where(is_public: false) }
  scope :monthly, -> { where(billing_interval: 'monthly') }
  scope :yearly, -> { where(billing_interval: 'yearly') }
  scope :one_time, -> { where(billing_interval: 'one_time') }
  scope :free, -> { where(price_cents: 0) }
  scope :paid, -> { where('price_cents > 0') }
  scope :by_price, -> { order(:price_cents) }
  
  # Callbacks
  before_validation :generate_slug, if: :name_changed?
  before_save :validate_features_exist
  before_save :normalize_permissions
  after_create :log_plan_creation
  after_update :log_plan_updates
  
  # Pricing methods
  def free?
    price_cents.zero?
  end
  
  def paid?
    price_cents > 0
  end
  
  def price_dollars
    price_cents / 100.0
  end
  
  def price_dollars=(amount)
    self.price_cents = (amount.to_f * 100).round
  end
  
  def formatted_price
    if free?
      'Free'
    else
      "$#{price_dollars}#{billing_suffix}"
    end
  end
  
  def billing_suffix
    case billing_interval
    when 'monthly'
      '/month'
    when 'yearly'
      '/year'
    when 'one_time'
      ' one-time'
    else
      ''
    end
  end
  
  # Feature management
  def feature_enabled?(feature_slug)
    features.include?(feature_slug.to_s)
  end
  
  def enable_feature(feature_slug)
    return false unless app.app_features.exists?(slug: feature_slug)
    
    self.features = (features + [feature_slug.to_s]).uniq
    save
  end
  
  def disable_feature(feature_slug)
    self.features = features - [feature_slug.to_s]
    save
  end
  
  def enabled_app_features
    app.app_features.where(slug: features)
  end
  
  def available_features
    app.app_features.where.not(slug: features)
  end
  
  # Permission management
  def has_permission?(permission)
    permissions.include?(permission.to_s)
  end
  
  def add_permission(permission)
    self.permissions = (permissions + [permission.to_s]).uniq
    save
  end
  
  def remove_permission(permission)
    self.permissions = permissions - [permission.to_s]
    save
  end
  
  # Limit management
  def get_limit(limit_name)
    limits[limit_name.to_s]
  end
  
  def set_limit(limit_name, value)
    self.limits = limits.merge(limit_name.to_s => value)
    save
  end
  
  def within_limit?(limit_name, current_usage)
    limit_value = get_limit(limit_name)
    return true if limit_value.nil? || limit_value == -1 # No limit or unlimited
    
    current_usage <= limit_value
  end
  
  # Subscription methods
  def subscriber_count
    app_subscriptions.active.count
  end
  
  def monthly_revenue
    return 0 unless monthly?
    
    subscriber_count * price_dollars
  end
  
  def yearly_revenue
    return 0 unless yearly?
    
    subscriber_count * price_dollars
  end
  
  def one_time_revenue
    return 0 unless one_time?
    
    app_subscriptions.count * price_dollars
  end
  
  def total_revenue
    case billing_interval
    when 'monthly'
      monthly_revenue * 12 # Annualized
    when 'yearly'
      yearly_revenue
    when 'one_time'
      one_time_revenue
    end
  end
  
  # Comparison methods
  def compare_to(other_plan)
    return nil unless other_plan.is_a?(AppPlan) && other_plan.app == app
    
    {
      price_difference: price_cents - other_plan.price_cents,
      feature_differences: {
        added: features - other_plan.features,
        removed: other_plan.features - features
      },
      permission_differences: {
        added: permissions - other_plan.permissions,
        removed: other_plan.permissions - permissions
      },
      limit_differences: calculate_limit_differences(other_plan)
    }
  end
  
  def upgrade_from?(other_plan)
    return false unless other_plan.is_a?(AppPlan) && other_plan.app == app
    
    price_cents > other_plan.price_cents ||
      features.size > other_plan.features.size ||
      permissions.size > other_plan.permissions.size
  end
  
  # Activation methods
  def activate!
    update!(is_active: true)
    log_plan_activation
  end
  
  def deactivate!
    update!(is_active: false)
    log_plan_deactivation
  end
  
  def make_public!
    update!(is_public: true)
  end
  
  def make_private!
    update!(is_public: false)
  end
  
  # Clone method
  def duplicate(new_name = nil)
    new_plan = dup
    new_plan.name = new_name || "#{name} (Copy)"
    new_plan.slug = nil # Will be regenerated
    new_plan.is_active = false
    new_plan.features = features.dup
    new_plan.permissions = permissions.dup
    new_plan.limits = limits.dup
    new_plan.metadata = metadata.dup
    new_plan.save
    new_plan
  end
  
  private
  
  def generate_slug
    return if slug.present? && !name_changed?
    
    base_slug = name.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/-{2,}/, '-').gsub(/^-+|-+$/, '')
    candidate_slug = base_slug
    counter = 1
    
    while app.app_plans.exists?(slug: candidate_slug)
      candidate_slug = "#{base_slug}-#{counter}"
      counter += 1
    end
    
    self.slug = candidate_slug
  end
  
  def validate_features_exist
    return if features.empty?
    
    existing_features = app.app_features.pluck(:slug)
    invalid_features = features - existing_features
    
    if invalid_features.any?
      errors.add(:features, "contains non-existent features: #{invalid_features.join(', ')}")
      throw :abort
    end
  end
  
  def normalize_permissions
    self.permissions = permissions.map(&:to_s).uniq.compact
  end
  
  def calculate_limit_differences(other_plan)
    all_limit_names = (limits.keys + other_plan.limits.keys).uniq
    differences = {}
    
    all_limit_names.each do |limit_name|
      current_limit = limits[limit_name]
      other_limit = other_plan.limits[limit_name]
      
      if current_limit != other_limit
        differences[limit_name] = {
          current: current_limit,
          other: other_limit,
          change: current_limit.to_i - other_limit.to_i
        }
      end
    end
    
    differences
  end
  
  def log_plan_creation
    Rails.logger.info "App Plan created: #{name} (#{id}) for App #{app.name}"
  end
  
  def log_plan_updates
    return unless saved_changes.any?
    
    Rails.logger.info "App Plan updated: #{name} (#{id}) - Changes: #{saved_changes.keys.join(', ')}"
  end
  
  def log_plan_activation
    Rails.logger.info "App Plan activated: #{name} (#{id})"
  end
  
  def log_plan_deactivation
    Rails.logger.info "App Plan deactivated: #{name} (#{id})"
  end
end