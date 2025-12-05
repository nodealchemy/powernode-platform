# frozen_string_literal: true

class Api::V1::BillingController < ApplicationController
  before_action :authenticate_request

  def overview
    render_success(
      data: {
        outstanding: outstanding_amount,
        this_month: this_month_amount,
        collected: all_time_collected,
        success_rate: payment_success_rate,
        recent_invoices: recent_invoices_data,
        payment_methods: payment_methods_data
      }
    )
  end

  def payment_methods
    methods = current_account.payment_methods.includes(:user).order(created_at: :desc)

    render_success(
      data: {
        payment_methods: methods.map do |method|
          {
            id: method.id,
            provider: method.provider,
            payment_method_type: method.payment_method_type,
            card_brand: method.card_brand,
            card_last_four: method.card_last_four,
            bank_account_last_four: method.bank_account_last_four,
            is_default: method.is_default,
            created_at: method.created_at
          }
        end
      }
    )
  end

  def create_payment_method
    processor = PaymentProcessingService.new(
      account: current_account,
      user: current_user
    )

    result = processor.attach_payment_method(
      payment_method_id: params[:payment_method_id],
      provider: params[:provider] || 'stripe'
    )

    if result[:success]
      render_success(
        data: {
          payment_method: {
            id: result[:payment_method].id,
            provider: result[:payment_method].provider,
            payment_method_type: result[:payment_method].payment_method_type,
            card_brand: result[:payment_method].card_brand,
            card_last_four: result[:payment_method].card_last_four
          }
        }
      )
    else
      render_error(result[:error], status: :unprocessable_content)
    end
  end

  def create_payment_intent
    processor = PaymentProcessingService.new(
      account: current_account,
      user: current_user
    )

    result = processor.create_payment_intent(
      amount_cents: params[:amount_cents].to_i,
      currency: params[:currency] || 'USD',
      description: params[:description]
    )

    if result[:success]
      render_success(
        data: {
          client_secret: result[:client_secret],
          payment_intent_id: result[:payment_intent].id
        }
      )
    else
      render_error(result[:error], status: :unprocessable_content)
    end
  end

  def invoices
    page = params[:page]&.to_i || 1
    per_page = [params[:per_page]&.to_i || 20, 100].min
    
    invoices_query = current_account.invoices.includes(:invoice_line_items)
                                             .order(created_at: :desc)
    
    total_count = invoices_query.count
    invoices = invoices_query.limit(per_page).offset((page - 1) * per_page)

    render_success(
      data: {
        invoices: invoices.map do |invoice|
          {
            id: invoice.id,
            invoice_number: invoice.invoice_number,
            subtotal: invoice.subtotal.to_s,
            tax_amount: invoice.tax_amount.to_s,
            total_amount: invoice.total_amount.to_s,
            currency: invoice.currency,
            status: invoice.status,
            due_date: invoice.due_date,
            created_at: invoice.created_at,
            line_items_count: invoice.invoice_line_items.count
          }
        end,
        pagination: {
          current_page: page,
          per_page: per_page,
          total_count: total_count,
          total_pages: (total_count / per_page.to_f).ceil
        }
      }
    )
  end

  def create_invoice
    invoice = current_account.invoices.build(invoice_params)
    invoice.status = 'draft'
    
    if invoice.save
      # Add line items if provided
      if params[:line_items].present?
        params[:line_items].each do |line_item_params|
          invoice.add_line_item(
            description: line_item_params[:description],
            quantity: line_item_params[:quantity].to_i,
            unit_amount_cents: (line_item_params[:unit_price].to_f * 100).to_i
          )
        end
        
        invoice.calculate_totals
      end

      render_success(
        data: {
          invoice: {
            id: invoice.id,
            invoice_number: invoice.invoice_number,
            total_amount: invoice.total_amount.to_s,
            status: invoice.status
          }
        }
      )
    else
      render_validation_error(invoice)
    end
  end

  def subscription_billing
    subscription = current_account.subscription
    
    if subscription.blank?
      render_error('No active subscription', status: :not_found)
      return
    end

    render_success(
      data: {
        subscription: {
          id: subscription.id,
          plan: {
            id: subscription.plan.id,
            name: subscription.plan.name,
            price: subscription.plan.price.to_s,
            billing_cycle: subscription.plan.billing_cycle
          },
          status: subscription.status,
          current_period_start: subscription.current_period_start,
          current_period_end: subscription.current_period_end,
          trial_end: subscription.trial_end,
          canceled_at: subscription.canceled_at
        },
        upcoming_invoice: upcoming_invoice_data(subscription),
        billing_history: billing_history_data(subscription)
      }
    )
  end

  private

  def outstanding_amount
    current_account.invoices.where(status: ['sent', 'overdue']).sum(:total_cents)
  end

  def this_month_amount
    current_account.invoices.where(
      created_at: Date.current.beginning_of_month..Date.current.end_of_month
    ).sum(:total_cents)
  end

  def all_time_collected
    current_account.payments.where(status: 'succeeded').sum(:amount_cents)
  end

  def payment_success_rate
    total_payments = current_account.payments.count
    return 0 if total_payments.zero?
    
    successful_payments = current_account.payments.where(status: 'succeeded').count
    (successful_payments.to_f / total_payments * 100).round(1)
  end

  def recent_invoices_data
    current_account.invoices.includes(:invoice_line_items)
                            .order(created_at: :desc)
                            .limit(5)
                            .map do |invoice|
      {
        id: invoice.id,
        invoice_number: invoice.invoice_number,
        subtotal: invoice.subtotal.to_s,
        total_amount: invoice.total_amount.to_s,
        currency: invoice.currency,
        status: invoice.status,
        due_date: invoice.due_date,
        created_at: invoice.created_at
      }
    end
  end

  def payment_methods_data
    current_account.payment_methods.where(is_default: true).limit(3).map do |method|
      {
        id: method.id,
        provider: method.provider,
        payment_method_type: method.payment_method_type,
        card_brand: method.card_brand,
        card_last_four: method.card_last_four,
        is_default: method.is_default
      }
    end
  end

  def upcoming_invoice_data(subscription)
    # This would calculate the next invoice for the subscription
    return nil unless subscription.active? || subscription.trialing?

    {
      amount_due: subscription.plan.price_cents,
      currency: subscription.plan.currency,
      next_payment_date: subscription.current_period_end,
      description: "#{subscription.plan.name} subscription"
    }
  end

  def billing_history_data(subscription)
    subscription.invoices.order(created_at: :desc).limit(12).map do |invoice|
      {
        id: invoice.id,
        invoice_number: invoice.invoice_number,
        amount: invoice.total_amount.to_s,
        status: invoice.status,
        created_at: invoice.created_at
      }
    end
  end

  def invoice_params
    params.require(:invoice).permit(:currency, :due_date, :notes)
  end
end