class GatewayConfiguration < ApplicationRecord
  validates :provider, presence: true, inclusion: { in: %w[stripe paypal] }
  validates :key_name, presence: true
  validates :encrypted_value, presence: true

  # Encrypt sensitive configuration values
  encrypts :encrypted_value, deterministic: false

  scope :for_provider, ->(provider) { where(provider: provider) }

  def self.set_config(provider, key, value)
    config = find_or_initialize_by(provider: provider, key_name: key)
    config.encrypted_value = value
    config.save!
  end

  def self.get_config(provider, key)
    config = find_by(provider: provider, key_name: key)
    config&.encrypted_value
  end

  def self.stripe_config
    {
      publishable_key: get_config('stripe', 'publishable_key'),
      secret_key: get_config('stripe', 'secret_key'),
      endpoint_secret: get_config('stripe', 'endpoint_secret'),
      webhook_tolerance: get_config('stripe', 'webhook_tolerance')&.to_i || 300
    }
  end

  def self.paypal_config
    {
      client_id: get_config('paypal', 'client_id'),
      client_secret: get_config('paypal', 'client_secret'),
      webhook_id: get_config('paypal', 'webhook_id'),
      mode: get_config('paypal', 'mode') || 'sandbox'
    }
  end
end