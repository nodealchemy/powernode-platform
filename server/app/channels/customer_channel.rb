# frozen_string_literal: true

class CustomerChannel < ApplicationCable::Channel
  def subscribed
    account_id = params[:account_id]
    
    if current_user && authorized_for_account?(account_id) && admin_user?
      stream_from("customer_updates_#{account_id}")
      
      Rails.logger.info "Admin user #{current_user.id} subscribed to customer updates for account #{account_id}"
      
      # Send welcome message with initial data
      transmit({
        type: 'connection_established',
        message: 'Connected to customer updates',
        timestamp: Time.current.iso8601
      })
    else
      Rails.logger.warn "Unauthorized customer updates subscription attempt for account #{account_id} by user #{current_user&.id}"
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "User #{current_user&.id} unsubscribed from customer updates"
  end

  # Handle real-time customer search
  def search(data)
    return unless admin_user?
    
    search_query = data['query'].to_s.strip
    filters = data['filters'] || {}
    
    # Perform search
    accounts_query = build_search_query(search_query, filters)
    results = accounts_query.includes(:users, :subscription, subscription: :plan)
                           .limit(10)
                           .map { |account| serialize_customer(account) }
    
    transmit({
      type: 'search_results',
      query: search_query,
      results: results,
      timestamp: Time.current.iso8601
    })
  end

  # Handle customer status changes
  def update_customer_status(data)
    return unless admin_user?
    
    account_id = data['customer_id']
    new_status = data['status']
    
    account = Account.find_by(id: account_id)
    return unless account
    
    if account.update(status: new_status)
      # Broadcast the change
      broadcast_data = {
        type: 'customer_updated',
        event: 'status_changed',
        customer: serialize_customer(account),
        timestamp: Time.current.iso8601
      }
      
      # Broadcast to all admin accounts
      admin_accounts = Account.joins(users: :roles).where(roles: { name: ['Owner', 'Admin'] }).distinct
      admin_accounts.each do |admin_account|
        ActionCable.server.broadcast("customer_updates_#{admin_account.id}", broadcast_data)
      end
      
      transmit({
        type: 'update_success',
        message: "Customer status updated to #{new_status}",
        customer_id: account_id,
        timestamp: Time.current.iso8601
      })
    else
      transmit({
        type: 'update_error',
        message: 'Failed to update customer status',
        errors: account.errors.full_messages,
        timestamp: Time.current.iso8601
      })
    end
  end

  # Handle ping for connection testing
  def ping(data = {})
    transmit({
      type: 'pong',
      server_timestamp: Time.current.iso8601,
      customer_count: Account.count
    })
  end

  private

  def admin_user?
    current_user&.roles&.any? { |role| ['Owner', 'Admin'].include?(role.name) }
  end

  def build_search_query(search_query, filters = {})
    accounts = Account.joins(:users)
    
    # Apply search filter
    if search_query.present?
      search = "%#{search_query}%"
      accounts = accounts.where(
        "accounts.name ILIKE ? OR users.email ILIKE ? OR users.first_name ILIKE ? OR users.last_name ILIKE ?",
        search, search, search, search
      )
    end
    
    # Apply status filter
    if filters['status'].present? && filters['status'] != 'all'
      accounts = accounts.where(status: filters['status'])
    end
    
    # Apply plan filter
    if filters['plan'].present? && filters['plan'] != 'all'
      accounts = accounts.joins(:subscription).where(subscriptions: { plan_id: filters['plan'] })
    end
    
    accounts.distinct.order(created_at: :desc)
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
end