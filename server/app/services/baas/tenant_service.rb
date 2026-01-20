# frozen_string_literal: true

module BaaS
  class TenantService
    attr_reader :tenant, :account

    def initialize(tenant: nil, account: nil)
      @tenant = tenant
      @account = account
    end

    # Create a new BaaS tenant
    def create_tenant(params)
      return { success: false, error: "Account required" } unless account

      existing = account.baas_tenants.active.first
      if existing
        return { success: false, error: "Account already has an active tenant" }
      end

      tenant = account.baas_tenants.build(
        name: params[:name],
        slug: params[:slug],
        tier: params[:tier] || "starter",
        environment: params[:environment] || "production",
        webhook_url: params[:webhook_url],
        default_currency: params[:default_currency] || "usd",
        timezone: params[:timezone] || "UTC",
        branding: params[:branding] || {},
        metadata: params[:metadata] || {}
      )

      tenant.apply_tier_limits!

      if tenant.save
        { success: true, tenant: tenant }
      else
        { success: false, errors: tenant.errors.full_messages }
      end
    end

    # Update tenant settings
    def update_tenant(params)
      return { success: false, error: "Tenant not found" } unless tenant

      allowed_params = params.slice(
        :name, :webhook_url, :webhook_secret, :default_currency,
        :timezone, :branding, :metadata
      )

      if tenant.update(allowed_params)
        { success: true, tenant: tenant }
      else
        { success: false, errors: tenant.errors.full_messages }
      end
    end

    # Upgrade/downgrade tenant tier
    def change_tier(new_tier)
      return { success: false, error: "Tenant not found" } unless tenant
      return { success: false, error: "Invalid tier" } unless %w[free starter pro enterprise].include?(new_tier)

      old_tier = tenant.tier
      tenant.tier = new_tier
      tenant.apply_tier_limits!

      if tenant.save
        Rails.logger.info "Tenant #{tenant.id} tier changed from #{old_tier} to #{new_tier}"
        { success: true, tenant: tenant, old_tier: old_tier, new_tier: new_tier }
      else
        { success: false, errors: tenant.errors.full_messages }
      end
    end

    # Suspend tenant
    def suspend_tenant(reason: nil)
      return { success: false, error: "Tenant not found" } unless tenant
      return { success: false, error: "Tenant already suspended" } if tenant.suspended?

      if tenant.update(status: "suspended", metadata: tenant.metadata.merge(suspension_reason: reason, suspended_at: Time.current))
        Rails.logger.info "Tenant #{tenant.id} suspended: #{reason}"
        { success: true, tenant: tenant }
      else
        { success: false, errors: tenant.errors.full_messages }
      end
    end

    # Reactivate suspended tenant
    def reactivate_tenant
      return { success: false, error: "Tenant not found" } unless tenant
      return { success: false, error: "Tenant not suspended" } unless tenant.suspended?

      if tenant.update(status: "active", metadata: tenant.metadata.merge(reactivated_at: Time.current))
        Rails.logger.info "Tenant #{tenant.id} reactivated"
        { success: true, tenant: tenant }
      else
        { success: false, errors: tenant.errors.full_messages }
      end
    end

    # Terminate tenant (permanent)
    def terminate_tenant
      return { success: false, error: "Tenant not found" } unless tenant

      ActiveRecord::Base.transaction do
        # Revoke all API keys
        tenant.api_keys.update_all(status: "revoked")

        # Mark tenant as terminated
        tenant.update!(status: "terminated", metadata: tenant.metadata.merge(terminated_at: Time.current))
      end

      Rails.logger.info "Tenant #{tenant.id} terminated"
      { success: true, tenant: tenant }
    rescue StandardError => e
      { success: false, error: e.message }
    end

    # Get tenant dashboard statistics
    def dashboard_stats
      return { success: false, error: "Tenant not found" } unless tenant

      thirty_days_ago = 30.days.ago

      stats = {
        overview: {
          total_customers: tenant.total_customers,
          total_subscriptions: tenant.total_subscriptions,
          total_invoices: tenant.total_invoices,
          total_revenue: tenant.total_revenue_processed,
          active_subscriptions: tenant.subscriptions.active.count
        },
        limits: {
          tier: tenant.tier,
          max_customers: tenant.max_customers,
          customers_used: tenant.total_customers,
          max_subscriptions: tenant.max_subscriptions,
          subscriptions_used: tenant.total_subscriptions,
          max_api_requests: tenant.max_api_requests_per_day,
          api_requests_today: tenant.api_requests_today
        },
        recent_activity: {
          new_customers_30d: tenant.customers.where("created_at > ?", thirty_days_ago).count,
          new_subscriptions_30d: tenant.subscriptions.where("created_at > ?", thirty_days_ago).count,
          invoices_30d: tenant.invoices.where("created_at > ?", thirty_days_ago).count,
          revenue_30d: tenant.invoices.paid.where("paid_at > ?", thirty_days_ago).sum(:total_cents) / 100.0
        },
        billing_config: tenant.billing_configuration&.settings_summary
      }

      { success: true, stats: stats }
    end

    # Check tenant rate limits
    def check_rate_limits
      return { success: false, error: "Tenant not found" } unless tenant

      {
        can_create_customer: tenant.can_create_customer?,
        can_create_subscription: tenant.can_create_subscription?,
        can_make_api_request: tenant.can_make_api_request?,
        customers_remaining: tenant.max_customers ? [tenant.max_customers - tenant.total_customers, 0].max : nil,
        subscriptions_remaining: tenant.max_subscriptions ? [tenant.max_subscriptions - tenant.total_subscriptions, 0].max : nil,
        api_requests_remaining: tenant.max_api_requests_per_day ? [tenant.max_api_requests_per_day - tenant.api_requests_today, 0].max : nil
      }
    end
  end
end
