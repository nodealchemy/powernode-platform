# frozen_string_literal: true

class Api::V1::CustomersController < ApplicationController
  before_action :authenticate_request

  def index
    page = params[:page]&.to_i || 1
    per_page = [params[:per_page]&.to_i || 20, 100].min
    
    # Build query based on filters
    accounts_query = build_accounts_query
    
    total_count = accounts_query.count
    accounts = accounts_query.includes(:users, :subscription, subscription: :plan)
                              .limit(per_page)
                              .offset((page - 1) * per_page)

    render json: {
      customers: accounts.map { |account| serialize_customer(account) },
      pagination: {
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: (total_count / per_page.to_f).ceil
      },
      stats: customer_stats
    }
  end

  def show
    account = Account.includes(:users, :subscription, subscription: :plan).find(params[:id])
    
    render json: {
      customer: serialize_detailed_customer(account)
    }
  end

  def create
    account_data = customer_params.slice(:name, :subdomain)
    user_data = customer_params.slice(:first_name, :last_name, :email)
    plan_id = customer_params[:plan_id]

    Account.transaction do
      # Create account
      @account = Account.create!(account_data.merge(status: 'active'))
      
      # Create subscription if plan provided
      if plan_id.present?
        plan = Plan.find(plan_id)
        @subscription = Subscription.create!(
          account: @account,
          plan: plan,
          status: 'active',
          current_period_start: Time.current,
          current_period_end: 1.month.from_now
        )
      end
      
      # Create primary user
      @user = User.create!(
        user_data.merge(
          account: @account,
          password: SecureRandom.alphanumeric(16),
          status: 'active',
          email_verified: false
        )
      )
      
      # Assign default role
      default_role = plan&.default_roles&.first || 'Member'
      role = Role.find_by(name: default_role)
      @user.assign_role(role) if role
    end

    # Broadcast customer creation
    broadcast_customer_change('created', @account)
    
    render json: {
      success: true,
      customer: serialize_customer(@account)
    }, status: :created
    
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      success: false,
      errors: e.record.errors.full_messages
    }, status: :unprocessable_content
  end

  def update
    account = Account.find(params[:id])
    
    Account.transaction do
      if customer_params[:subscription_attributes].present?
        subscription_data = customer_params[:subscription_attributes]
        if account.subscription
          account.subscription.update!(subscription_data)
        else
          account.create_subscription!(subscription_data)
        end
      end
      
      account.update!(customer_params.except(:subscription_attributes, :first_name, :last_name, :email, :plan_id))
      
      # Update primary user if user data provided
      if customer_params.slice(:first_name, :last_name, :email).any?
        primary_user = account.users.owners.first || account.users.first
        primary_user&.update!(customer_params.slice(:first_name, :last_name, :email))
      end
    end

    # Broadcast customer update
    broadcast_customer_change('updated', account)
    
    render json: {
      success: true,
      customer: serialize_customer(account.reload)
    }
    
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      success: false,
      errors: e.record.errors.full_messages
    }, status: :unprocessable_content
  end

  def destroy
    account = Account.find(params[:id])
    account.update!(status: 'inactive')
    
    # Broadcast customer deletion/deactivation
    broadcast_customer_change('deactivated', account)
    
    render_success
  end

  def stats
    render json: customer_stats
  end

  private

  def build_accounts_query
    # Start with Account query
    accounts = Account.all
    
    # Build subquery for account IDs that match criteria
    account_ids_query = Account.joins(:users)
    
    # Filter by search query
    if params[:search].present?
      search = "%#{params[:search]}%"
      account_ids_query = account_ids_query.where(
        "accounts.name ILIKE ? OR users.email ILIKE ? OR users.first_name ILIKE ? OR users.last_name ILIKE ?",
        search, search, search, search
      )
    end
    
    # Filter by status
    if params[:status].present? && params[:status] != 'all'
      account_ids_query = account_ids_query.where(accounts: { status: params[:status] })
    end
    
    # Filter by plan
    if params[:plan].present? && params[:plan] != 'all'
      account_ids_query = account_ids_query.joins(:subscription).where(subscriptions: { plan_id: params[:plan] })
    end
    
    # Get distinct account IDs and apply to main query
    matching_account_ids = account_ids_query.select("accounts.id").distinct.pluck(:id)
    accounts = accounts.where(id: matching_account_ids) if matching_account_ids.any?
    
    accounts.order(created_at: :desc)
  end

  def serialize_customer(account)
    primary_user = account.users.owners.first || account.users.first
    subscription = account.subscription
    
    {
      id: account.id,
      name: account.name,
      subdomain: account.subdomain,
      status: account.status,
      created_at: account.created_at,
      updated_at: account.updated_at,
      user: primary_user ? {
        id: primary_user.id,
        first_name: primary_user.first_name,
        last_name: primary_user.last_name,
        full_name: primary_user.full_name,
        email: primary_user.email,
        email_verified: primary_user.email_verified?,
        last_login_at: primary_user.last_login_at
      } : nil,
      subscription: subscription ? {
        id: subscription.id,
        status: subscription.status,
        plan: {
          id: subscription.plan.id,
          name: subscription.plan.name,
          price_cents: subscription.plan.price_cents
        },
        current_period_start: subscription.current_period_start,
        current_period_end: subscription.current_period_end,
        trial_end: subscription.trial_end
      } : nil,
      mrr: calculate_mrr(account),
      total_users: account.users.count
    }
  end

  def serialize_detailed_customer(account)
    base_data = serialize_customer(account)
    base_data.merge({
      payment_methods: account.payment_methods.count,
      total_invoices: account.invoices.count,
      total_payments: account.payments.count,
      lifetime_value: account.payments.where(status: 'succeeded').sum(:amount_cents),
      recent_activity: recent_activity(account)
    })
  end

  def calculate_mrr(account)
    return 0 unless account.subscription&.active?
    
    monthly_amount = case account.subscription.plan.billing_cycle
    when 'monthly'
      account.subscription.plan.price_cents
    when 'yearly'
      account.subscription.plan.price_cents / 12
    else
      0
    end
    
    monthly_amount
  end

  def recent_activity(account)
    activities = []
    
    # Recent payments
    account.payments.order(created_at: :desc).limit(5).each do |payment|
      activities << {
        type: 'payment',
        description: "Payment #{payment.status}",
        amount: payment.amount_cents,
        timestamp: payment.created_at
      }
    end
    
    # Recent logins
    account.users.where.not(last_login_at: nil).order(last_login_at: :desc).limit(3).each do |user|
      activities << {
        type: 'login',
        description: "#{user.full_name} logged in",
        timestamp: user.last_login_at
      }
    end
    
    activities.sort_by { |a| a[:timestamp] }.reverse.first(10)
  end

  def customer_stats
    current_time = Time.current
    
    {
      total_customers: Account.count,
      active_customers: Account.where(status: 'active').count,
      active_subscriptions: Subscription.where(status: ['active', 'trialing']).count,
      new_this_month: Account.where(created_at: current_time.beginning_of_month..current_time.end_of_month).count,
      total_mrr: calculate_total_mrr,
      churn_rate: calculate_churn_rate
    }
  end

  def calculate_total_mrr
    Subscription.joins(:plan).where(status: ['active', 'trialing']).sum do |subscription|
      case subscription.plan.billing_cycle
      when 'monthly'
        subscription.plan.price_cents
      when 'yearly'
        subscription.plan.price_cents / 12
      else
        0
      end
    end
  end

  def calculate_churn_rate
    # Simple churn rate calculation for last 30 days
    start_of_month = 30.days.ago
    customers_at_start = Account.where('created_at < ?', start_of_month).count
    churned_customers = Account.where(status: 'inactive', updated_at: start_of_month..Time.current).count
    
    return 0 if customers_at_start == 0
    (churned_customers.to_f / customers_at_start * 100).round(2)
  end

  def broadcast_customer_change(event_type, account)
    # Broadcast to all admin users
    data = {
      type: 'customer_updated',
      event: event_type,
      customer: serialize_customer(account),
      stats: customer_stats,
      timestamp: Time.current.iso8601
    }
    
    # Find all admin accounts that should receive this update
    admin_accounts = Account.joins(users: :roles).where(roles: { name: ['Owner', 'Admin'] }).distinct
    
    admin_accounts.each do |admin_account|
      ActionCable.server.broadcast("customer_updates_#{admin_account.id}", data)
    end
  end

  def customer_params
    params.require(:customer).permit(
      :name, :subdomain, :status, :first_name, :last_name, :email, :plan_id,
      subscription_attributes: [:plan_id, :status]
    )
  end
end