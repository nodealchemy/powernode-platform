# frozen_string_literal: true

module BaaS
  class BillingConfiguration < ApplicationRecord
    self.table_name = "baas_billing_configurations"

    # Associations
    belongs_to :baas_tenant, class_name: "BaaS::Tenant"

    # Validations
    validates :invoice_prefix, length: { maximum: 10 }
    validates :invoice_due_days, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 90 }
    validates :dunning_attempts, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }
    validates :dunning_interval_days, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 30 }
    validates :platform_fee_percentage, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 50 }
    validates :default_trial_days, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 365 }

    # Instance methods
    def stripe_connected?
      stripe_connected && stripe_account_id.present?
    end

    def paypal_connected?
      paypal_connected && paypal_merchant_id.present?
    end

    def any_gateway_connected?
      stripe_connected? || paypal_connected?
    end

    def connect_stripe!(account_id, status: "active")
      update!(
        stripe_account_id: account_id,
        stripe_account_status: status,
        stripe_connected: true
      )
    end

    def disconnect_stripe!
      update!(
        stripe_account_id: nil,
        stripe_account_status: "not_connected",
        stripe_connected: false
      )
    end

    def connect_paypal!(merchant_id)
      update!(
        paypal_merchant_id: merchant_id,
        paypal_connected: true
      )
    end

    def disconnect_paypal!
      update!(
        paypal_merchant_id: nil,
        paypal_connected: false
      )
    end

    def calculate_platform_fee(amount)
      (amount * platform_fee_percentage / 100.0).round(2)
    end

    def settings_summary
      {
        stripe_connected: stripe_connected?,
        paypal_connected: paypal_connected?,
        auto_invoice: auto_invoice,
        auto_charge: auto_charge,
        invoice_due_days: invoice_due_days,
        tax_enabled: tax_enabled,
        dunning_enabled: dunning_enabled,
        usage_billing_enabled: usage_billing_enabled,
        metered_billing_enabled: metered_billing_enabled,
        trial_enabled: trial_enabled,
        default_trial_days: default_trial_days,
        platform_fee_percentage: platform_fee_percentage
      }
    end
  end
end
