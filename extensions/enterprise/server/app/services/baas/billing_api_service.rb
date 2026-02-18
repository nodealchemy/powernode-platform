# frozen_string_literal: true

module BaaS
  class BillingApiService
    attr_reader :tenant

    def initialize(tenant:)
      @tenant = tenant
    end

    # ==================== CUSTOMERS ====================

    def create_customer(params)
      return { success: false, error: "Tenant not found" } unless tenant
      return { success: false, error: "Customer limit reached" } unless tenant.can_create_customer?

      customer = tenant.customers.build(
        external_id: params[:external_id] || SecureRandom.uuid,
        email: params[:email],
        name: params[:name],
        address_line1: params[:address_line1],
        address_line2: params[:address_line2],
        city: params[:city],
        state: params[:state],
        postal_code: params[:postal_code],
        country: params[:country],
        tax_id: params[:tax_id],
        tax_id_type: params[:tax_id_type],
        tax_exempt: params[:tax_exempt] || false,
        currency: params[:currency] || tenant.default_currency,
        metadata: params[:metadata] || {}
      )

      if customer.save
        { success: true, customer: customer.summary }
      else
        { success: false, errors: customer.errors.full_messages }
      end
    end

    def get_customer(external_id)
      customer = tenant.customers.find_by(external_id: external_id)
      return { success: false, error: "Customer not found" } unless customer
      { success: true, customer: customer.summary }
    end

    def update_customer(external_id, params)
      customer = tenant.customers.find_by(external_id: external_id)
      return { success: false, error: "Customer not found" } unless customer

      allowed = params.slice(
        :email, :name, :address_line1, :address_line2, :city, :state,
        :postal_code, :country, :tax_id, :tax_id_type, :tax_exempt, :metadata
      )

      if customer.update(allowed)
        { success: true, customer: customer.summary }
      else
        { success: false, errors: customer.errors.full_messages }
      end
    end

    def list_customers(params = {})
      customers = tenant.customers
      customers = customers.active if params[:status] == "active"
      customers = customers.archived if params[:status] == "archived"
      customers = customers.where("email ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:email])}%") if params[:email].present?

      paginated = customers.order(created_at: :desc).page(params[:page] || 1).per([ params[:per_page]&.to_i || 25, 100 ].min)

      {
        success: true,
        customers: paginated.map(&:summary),
        pagination: pagination_meta(paginated)
      }
    end

    # ==================== SUBSCRIPTIONS ====================

    def create_subscription(params)
      return { success: false, error: "Tenant not found" } unless tenant
      return { success: false, error: "Subscription limit reached" } unless tenant.can_create_subscription?

      customer = tenant.customers.find_by(external_id: params[:customer_id])
      return { success: false, error: "Customer not found" } unless customer

      config = tenant.billing_configuration
      trial_end = nil
      if config&.trial_enabled && params[:trial_days].to_i > 0
        trial_end = Time.current + params[:trial_days].to_i.days
      elsif config&.trial_enabled && config.default_trial_days > 0 && params[:trial_days] != 0
        trial_end = Time.current + config.default_trial_days.days
      end

      subscription = tenant.subscriptions.build(
        baas_customer: customer,
        external_id: params[:external_id] || SecureRandom.uuid,
        plan_external_id: params[:plan_id],
        status: trial_end ? "trialing" : "active",
        billing_interval: params[:billing_interval] || "month",
        billing_interval_count: params[:billing_interval_count] || 1,
        unit_amount: params[:unit_amount],
        currency: params[:currency] || customer.currency,
        quantity: params[:quantity] || 1,
        current_period_start: Date.current,
        current_period_end: calculate_period_end(Date.current, params[:billing_interval] || "month", params[:billing_interval_count] || 1),
        trial_end: trial_end,
        metadata: params[:metadata] || {}
      )

      if subscription.save
        { success: true, subscription: subscription.summary }
      else
        { success: false, errors: subscription.errors.full_messages }
      end
    end

    def get_subscription(external_id)
      subscription = tenant.subscriptions.find_by(external_id: external_id)
      return { success: false, error: "Subscription not found" } unless subscription
      { success: true, subscription: subscription.summary }
    end

    def update_subscription(external_id, params)
      subscription = tenant.subscriptions.find_by(external_id: external_id)
      return { success: false, error: "Subscription not found" } unless subscription

      allowed = params.slice(:plan_external_id, :quantity, :metadata)

      if subscription.update(allowed)
        { success: true, subscription: subscription.summary }
      else
        { success: false, errors: subscription.errors.full_messages }
      end
    end

    def cancel_subscription(external_id, params = {})
      subscription = tenant.subscriptions.find_by(external_id: external_id)
      return { success: false, error: "Subscription not found" } unless subscription

      at_period_end = params[:at_period_end] != false
      subscription.cancel!(reason: params[:reason], at_period_end: at_period_end)

      { success: true, subscription: subscription.reload.summary }
    end

    def list_subscriptions(params = {})
      subscriptions = tenant.subscriptions
      subscriptions = subscriptions.where(status: params[:status]) if params[:status].present?

      if params[:customer_id].present?
        customer = tenant.customers.find_by(external_id: params[:customer_id])
        subscriptions = subscriptions.where(baas_customer: customer) if customer
      end

      paginated = subscriptions.order(created_at: :desc).page(params[:page] || 1).per([ params[:per_page]&.to_i || 25, 100 ].min)

      {
        success: true,
        subscriptions: paginated.map(&:summary),
        pagination: pagination_meta(paginated)
      }
    end

    # ==================== INVOICES ====================

    def create_invoice(params)
      return { success: false, error: "Tenant not found" } unless tenant

      customer = tenant.customers.find_by(external_id: params[:customer_id])
      return { success: false, error: "Customer not found" } unless customer

      subscription = nil
      if params[:subscription_id].present?
        subscription = tenant.subscriptions.find_by(external_id: params[:subscription_id])
      end

      config = tenant.billing_configuration
      due_date = Time.current + (config&.invoice_due_days || 30).days

      invoice = tenant.invoices.build(
        baas_customer: customer,
        baas_subscription: subscription,
        external_id: params[:external_id] || SecureRandom.uuid,
        currency: params[:currency] || customer.currency,
        due_date: params[:due_date] || due_date,
        period_start: params[:period_start],
        period_end: params[:period_end],
        metadata: params[:metadata] || {}
      )

      if invoice.save
        # Add line items if provided
        params[:line_items]&.each do |item|
          invoice.add_line_item(
            description: item[:description],
            amount_cents: item[:amount_cents] || (item[:amount].to_f * 100).to_i,
            quantity: item[:quantity] || 1,
            metadata: item[:metadata] || {}
          )
        end

        { success: true, invoice: invoice.summary }
      else
        { success: false, errors: invoice.errors.full_messages }
      end
    end

    def get_invoice(external_id)
      invoice = tenant.invoices.find_by(external_id: external_id)
      return { success: false, error: "Invoice not found" } unless invoice

      { success: true, invoice: invoice.summary.merge(line_items: invoice.line_items) }
    end

    def finalize_invoice(external_id)
      invoice = tenant.invoices.find_by(external_id: external_id)
      return { success: false, error: "Invoice not found" } unless invoice
      return { success: false, error: "Invoice not in draft status" } unless invoice.draft?

      invoice.finalize!
      { success: true, invoice: invoice.summary }
    end

    def pay_invoice(external_id, params = {})
      invoice = tenant.invoices.find_by(external_id: external_id)
      return { success: false, error: "Invoice not found" } unless invoice
      return { success: false, error: "Invoice not open" } unless invoice.open?

      invoice.mark_paid!(payment_reference: params[:payment_reference])
      { success: true, invoice: invoice.summary }
    end

    def void_invoice(external_id, params = {})
      invoice = tenant.invoices.find_by(external_id: external_id)
      return { success: false, error: "Invoice not found" } unless invoice
      return { success: false, error: "Cannot void paid invoice" } if invoice.paid?

      invoice.void!(reason: params[:reason])
      { success: true, invoice: invoice.summary }
    end

    def list_invoices(params = {})
      invoices = tenant.invoices
      invoices = invoices.where(status: params[:status]) if params[:status].present?

      if params[:customer_id].present?
        customer = tenant.customers.find_by(external_id: params[:customer_id])
        invoices = invoices.where(baas_customer: customer) if customer
      end

      paginated = invoices.order(created_at: :desc).page(params[:page] || 1).per([ params[:per_page]&.to_i || 25, 100 ].min)

      {
        success: true,
        invoices: paginated.map(&:summary),
        pagination: pagination_meta(paginated)
      }
    end

    private

    def calculate_period_end(start_date, interval, count)
      case interval
      when "day" then start_date + count.days
      when "week" then start_date + count.weeks
      when "month" then start_date + count.months
      when "year" then start_date + count.years
      else start_date + 1.month
      end
    end

    def pagination_meta(paginated)
      {
        current_page: paginated.current_page,
        per_page: paginated.limit_value,
        total_pages: paginated.total_pages,
        total_count: paginated.total_count
      }
    end
  end
end
