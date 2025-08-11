class AuditLog < ApplicationRecord
  # Associations
  belongs_to :user, optional: true
  belongs_to :account

  # Validations
  validates :action, presence: true, inclusion: {
    in: %w[create update delete login logout payment subscription_change role_change 
           create_plan update_plan delete_plan toggle_plan_status 
           suspend_account activate_account admin_settings_update
           impersonation.started impersonation.ended]
  }
  validates :resource_type, presence: true
  validates :resource_id, presence: true
  validates :source, presence: true, inclusion: { in: %w[web api system webhook admin_panel] }

  # Serialization
  serialize :old_values, coder: JSON
  serialize :new_values, coder: JSON
  serialize :metadata, coder: JSON

  # Scopes
  scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
  scope :by_user, ->(user) { where(user: user) }
  scope :by_account, ->(account) { where(account: account) }
  scope :by_action, ->(action) { where(action: action) }
  scope :recent, -> { order(created_at: :desc) }
  scope :in_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # Advanced filtering scopes for admin interface
  scope :apply_filters, ->(filters) {
    scope = all
    scope = scope.where(action: filters[:action]) if filters[:action].present?
    scope = scope.joins(:user).where(users: { email: filters[:user_email] }) if filters[:user_email].present?
    scope = scope.joins(:account).where(accounts: { name: filters[:account_name] }) if filters[:account_name].present?
    scope = scope.where(resource_type: filters[:resource_type]) if filters[:resource_type].present?
    scope = scope.where(source: filters[:source]) if filters[:source].present?
    scope = scope.where(ip_address: filters[:ip_address]) if filters[:ip_address].present?
    scope = scope.where(created_at: filters[:date_from].beginning_of_day..) if filters[:date_from].present?
    scope = scope.where(created_at: ..filters[:date_to].end_of_day) if filters[:date_to].present?
    scope
  }

  # Callbacks
  after_initialize :set_defaults

  # Class methods
  def self.log_action(action:, resource:, user: nil, account:, old_values: nil, new_values: nil, **options)
    create!(
      action: action,
      resource_type: resource.class.name,
      resource_id: resource.id,
      user: user,
      account: account,
      old_values: old_values,
      new_values: new_values,
      ip_address: options[:ip_address],
      user_agent: options[:user_agent],
      source: options[:source] || "web",
      metadata: options[:metadata] || {}
    )
  end

  def self.log_login(user, **options)
    log_action(
      action: "login",
      resource: user,
      user: user,
      account: user.account,
      **options
    )
  end

  def self.log_logout(user, **options)
    log_action(
      action: "logout",
      resource: user,
      user: user,
      account: user.account,
      **options
    )
  end

  def self.log_payment(payment, **options)
    log_action(
      action: "payment",
      resource: payment,
      account: payment.account,
      new_values: {
        amount_cents: payment.amount_cents,
        status: payment.status,
        payment_method: payment.payment_method
      },
      **options
    )
  end

  def self.log_subscription_change(subscription, old_status, new_status, user: nil, **options)
    log_action(
      action: "subscription_change",
      resource: subscription,
      user: user,
      account: subscription.account,
      old_values: { status: old_status },
      new_values: { status: new_status },
      **options
    )
  end

  # Instance methods
  def resource
    return nil unless resource_type && resource_id
    resource_type.constantize.find_by(id: resource_id)
  rescue NameError, ActiveRecord::RecordNotFound
    nil
  end

  def actor
    user || "System"
  end

  def summary
    case action
    when "login"
      "#{actor} logged in"
    when "logout"
      "#{actor} logged out"
    when "create"
      "#{actor} created #{resource_type}"
    when "update"
      "#{actor} updated #{resource_type}"
    when "delete"
      "#{actor} deleted #{resource_type}"
    when "payment"
      amount = new_values&.dig("amount_cents")
      "Payment of $#{amount / 100.0 if amount} #{new_values&.dig('status')}"
    when "subscription_change"
      old_status = old_values&.dig("status")
      new_status = new_values&.dig("status")
      "Subscription changed from #{old_status} to #{new_status}"
    when "role_change"
      "#{actor} changed roles for #{resource_type}"
    else
      "#{actor} performed #{action} on #{resource_type}"
    end
  end

  def changes_summary
    return nil unless old_values.present? && new_values.present?

    changes = []
    new_values.each do |key, new_value|
      old_value = old_values[key]
      if old_value != new_value
        changes << "#{key}: #{old_value} → #{new_value}"
      end
    end

    changes.join(", ")
  end

  private

  def set_defaults
    self.old_values ||= {}
    self.new_values ||= {}
    self.metadata ||= {}
  end
end
