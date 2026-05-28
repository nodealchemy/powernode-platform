# frozen_string_literal: true

module Powernode
  # Core-side extension point for optional billing capabilities.
  #
  # Core never references the business `Billing::` namespace directly. The business
  # extension registers its models + handlers here at boot; when no extension is
  # present every accessor degrades safely (nil models, quota always allowed).
  #
  # This replaces the previous `defined?(Billing::X)` guards scattered through core
  # dashboards/controllers with a single clean interface.
  module BillingBridge
    class << self
      # Model classes registered by the business extension (nil in core mode).
      attr_accessor :subscription_model, :payment_model, :plan_model, :revenue_snapshot_model

      # Handler registered by the business extension to enforce provisioning quota.
      # A callable taking (account:, mission:) and returning a Hash:
      #   { allowed: true } or { allowed: false, payload: {...} }
      attr_writer :provisioning_quota_handler

      def provisioning_quota_handler
        @provisioning_quota_handler
      end

      # Enforce provisioning quota via the registered handler. Allows by default
      # (no handler registered = no billing extension = no quota limits).
      # @return [Hash] { allowed: Boolean, payload: Hash (present only on denial) }
      def check_provisioning_quota(account:, mission:)
        return { allowed: true } unless @provisioning_quota_handler

        @provisioning_quota_handler.call(account: account, mission: mission)
      rescue StandardError => e
        Rails.logger.error("[Powernode::BillingBridge] provisioning quota handler failed: #{e.message}")
        { allowed: true }
      end

      # Test/boot helper.
      def reset!
        @subscription_model = nil
        @payment_model = nil
        @plan_model = nil
        @revenue_snapshot_model = nil
        @provisioning_quota_handler = nil
      end
    end
  end
end
