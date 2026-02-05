# frozen_string_literal: true

# Comprehensive test data for development and testing environments
# This file is automatically loaded in development/test environments only

puts "📊 Loading comprehensive test data..."

# Get plan references
starter_plan = Plan.find_by(name: 'Starter')
professional_plan = Plan.find_by(name: 'Professional')
enterprise_plan = Plan.find_by(name: 'Enterprise')

# Create sample customer accounts
sample_customers = [
  {
    account: { name: 'Acme Corporation', subdomain: 'acme', status: 'active' },
    user: { first_name: 'John', last_name: 'Smith', email: 'john@acme.com' },
    plan: professional_plan,
    created_at: 3.months.ago
  },
  {
    account: { name: 'TechStart Inc', subdomain: 'techstart', status: 'active' },
    user: { first_name: 'Sarah', last_name: 'Johnson', email: 'sarah@techstart.io' },
    plan: starter_plan,
    created_at: 2.months.ago
  },
  {
    account: { name: 'Enterprise Solutions LLC', subdomain: 'enterprise-sol', status: 'active' },
    user: { first_name: 'Michael', last_name: 'Chen', email: 'michael@enterprisesol.com' },
    plan: enterprise_plan,
    created_at: 4.months.ago
  },
  {
    account: { name: 'StartupHub', subdomain: 'startuphub', status: 'active' },
    user: { first_name: 'Emily', last_name: 'Rodriguez', email: 'emily@startuphub.co' },
    plan: professional_plan,
    created_at: 1.month.ago
  },
  {
    account: { name: 'Digital Innovations', subdomain: 'digital-inn', status: 'active' },
    user: { first_name: 'David', last_name: 'Wilson', email: 'david@digitalinn.net' },
    plan: starter_plan,
    created_at: 6.weeks.ago
  },
  {
    account: { name: 'Global Tech Partners', subdomain: 'globaltech', status: 'active' },
    user: { first_name: 'Lisa', last_name: 'Anderson', email: 'lisa@globaltech.com' },
    plan: enterprise_plan,
    created_at: 5.months.ago
  },
  {
    account: { name: 'InnovateLab', subdomain: 'innovatelab', status: 'suspended' },
    user: { first_name: 'Robert', last_name: 'Taylor', email: 'robert@innovatelab.org' },
    plan: professional_plan,
    created_at: 2.months.ago
  },
  {
    account: { name: 'CloudFirst Systems', subdomain: 'cloudfirst', status: 'active' },
    user: { first_name: 'Jennifer', last_name: 'Brown', email: 'jennifer@cloudfirst.io' },
    plan: starter_plan,
    created_at: 3.weeks.ago
  },
  {
    account: { name: 'DevTeam Solutions', subdomain: 'devteam', status: 'active' },
    user: { first_name: 'Alex', last_name: 'Thompson', email: 'alex@devteam.co' },
    plan: professional_plan,
    created_at: 7.weeks.ago
  },
  {
    account: { name: 'NextGen Analytics', subdomain: 'nextgen', status: 'active' },
    user: { first_name: 'Maria', last_name: 'Garcia', email: 'maria@nextgenanalytics.ai' },
    plan: enterprise_plan,
    created_at: 6.months.ago
  }
]

sample_customers.each_with_index do |customer_data, index|
  # Create account
  account = Account.find_or_create_by!(name: customer_data[:account][:name]) do |acc|
    acc.subdomain = customer_data[:account][:subdomain]
    acc.status = customer_data[:account][:status]
    acc.billing_email = "billing@#{customer_data[:account][:subdomain]}.com"
    acc.created_at = customer_data[:created_at]
    acc.updated_at = customer_data[:created_at]
  end

  # Create subscription
  subscription = Subscription.find_or_create_by!(account: account) do |sub|
    sub.plan = customer_data[:plan]
    sub.status = customer_data[:account][:status] == 'suspended' ? 'past_due' : 'active'
    sub.current_period_start = customer_data[:created_at]
    sub.current_period_end = 1.month.from_now
    sub.trial_end = customer_data[:created_at] + customer_data[:plan].trial_days.days
    sub.quantity = 1
    sub.stripe_subscription_id = "sub_test_#{SecureRandom.hex(8)}"
    sub.metadata = {
      source: 'seed_data',
      test: true
    }
  end

  # Create owner user
  user = User.find_or_create_by!(email: customer_data[:user][:email]) do |u|
    u.account = account
    u.first_name = customer_data[:user][:first_name]
    u.last_name = customer_data[:user][:last_name]
    u.password = 'SecureTest789!@#$%'
    u.password_confirmation = 'SecureTest789!@#$%'
    u.status = 'active'
    u.role = 'owner'
    u.email_verified = true
    u.email_verified_at = customer_data[:created_at]
    u.last_login_at = rand(1..7).days.ago
  end

  # Create additional team members for some accounts
  if customer_data[:plan] == professional_plan || customer_data[:plan] == enterprise_plan
    rand(2..5).times do |member_index|
      team_member = User.find_or_create_by!(
        email: "team#{member_index}@#{customer_data[:account][:subdomain]}.com"
      ) do |u|
        u.account = account
        u.first_name = [ 'Alice', 'Bob', 'Charlie', 'Diana', 'Eve' ].sample
        u.last_name = [ 'Johnson', 'Williams', 'Brown', 'Jones', 'Davis' ].sample
        u.password = 'TeamSecure567!@#$%'
        u.password_confirmation = 'TeamSecure567!@#$%'
        u.status = 'active'
        u.role = member_index == 0 ? 'admin' : 'member'
        u.email_verified = true
        u.email_verified_at = customer_data[:created_at] + rand(1..30).days
        u.last_login_at = rand(1..14).days.ago
      end
    end
  end

  # Create payment method
  payment_method = PaymentMethod.find_or_create_by!(
    account: account,
    user: user,
    provider: 'stripe',
    external_id: "pm_test_#{SecureRandom.hex(8)}"
  ) do |pm|
    pm.payment_type = 'card'
    pm.brand = [ 'visa', 'mastercard', 'amex' ].sample
    pm.last_four = rand(1000..9999).to_s
    pm.exp_month = rand(1..12)
    pm.exp_year = Date.current.year + rand(1..4)
    pm.holder_name = "#{user.first_name} #{user.last_name}"
    pm.is_default = true
    pm.metadata = { test: true }
  end

  # Create invoices with payment history
  (1..rand(3..6)).each do |invoice_num|
    invoice_date = customer_data[:created_at] + (invoice_num - 1).months

    invoice_number = "INV-#{index.to_s.rjust(3, '0')}-#{invoice_num.to_s.rjust(4, '0')}-#{SecureRandom.hex(4).upcase}"
    invoice = Invoice.find_or_create_by!(
      subscription: subscription,
      invoice_number: invoice_number
    ) do |inv|
      inv.status = invoice_num == 1 && customer_data[:account][:status] == 'suspended' ? 'uncollectible' : 'paid'
      inv.subtotal_cents = customer_data[:plan].price_cents
      inv.tax_cents = (customer_data[:plan].price_cents * 0.1).to_i  # 10% tax
      inv.total_cents = inv.subtotal_cents + inv.tax_cents
      inv.currency = 'USD'
      inv.tax_rate = 0.1
      inv.due_date = invoice_date + 30.days
      inv.paid_at = inv.status == 'paid' ? invoice_date + rand(1..15).days : nil
      inv.stripe_invoice_id = "in_test_#{SecureRandom.hex(8)}"
      inv.metadata = {
        plan: customer_data[:plan].name,
        test: true
      }
    end

    # Create corresponding payment if invoice is paid and amount > 0
    if invoice.status == 'paid' && invoice.total_cents > 0
      payment = Payment.find_or_create_by!(
        invoice: invoice
      ) do |pay|
        pay.amount_cents = invoice.total_cents
        pay.currency = 'USD'
        pay.status = 'succeeded'
        pay.payment_method = 'stripe_card'
        pay.processed_at = invoice.paid_at
        pay.net_amount_cents = (invoice.total_cents * 0.971).to_i  # After 2.9% fee
        pay.gateway_fee_cents = (invoice.total_cents * 0.029).to_i  # 2.9% fee
        pay.metadata = {
          invoice_number: invoice.invoice_number,
          stripe_payment_intent_id: "pi_test_#{SecureRandom.hex(8)}",
          test: true
        }
      end
    end
  end
end

puts "  ✅ Created #{Account.count - 2} test customer accounts" # Subtract admin and demo

# Create webhook events for testing
puts "\n📮 Creating sample webhook events..."

webhook_events = [
  {
    event_type: 'customer.subscription.created',
    gateway: 'stripe',
    status: 'processed',
    payload: {
      id: 'evt_test_subscription_created',
      type: 'customer.subscription.created',
      data: {
        object: {
          id: 'sub_test_created',
          status: 'active',
          customer: 'cus_test_123'
        }
      }
    }
  },
  {
    event_type: 'payment_intent.succeeded',
    gateway: 'stripe',
    status: 'processed',
    payload: {
      id: 'evt_test_payment_succeeded',
      type: 'payment_intent.succeeded',
      data: {
        object: {
          id: 'pi_test_succeeded',
          amount: 2999,
          currency: 'usd',
          status: 'succeeded'
        }
      }
    }
  },
  {
    event_type: 'invoice.payment_failed',
    gateway: 'stripe',
    status: 'processed',
    payload: {
      id: 'evt_test_payment_failed',
      type: 'invoice.payment_failed',
      data: {
        object: {
          id: 'in_test_failed',
          amount_due: 9999,
          currency: 'usd',
          status: 'open'
        }
      }
    }
  },
  {
    event_type: 'customer.subscription.deleted',
    gateway: 'stripe',
    status: 'processed',
    payload: {
      id: 'evt_test_subscription_deleted',
      type: 'customer.subscription.deleted',
      data: {
        object: {
          id: 'sub_test_deleted',
          status: 'canceled',
          canceled_at: Time.current.to_i
        }
      }
    }
  }
]

webhook_events.each do |event_data|
  WebhookEvent.find_or_create_by!(
    external_id: event_data[:payload][:id],
    provider: event_data[:gateway]
  ) do |event|
    event.event_type = event_data[:event_type]
    event.status = event_data[:status]
    event.payload = event_data[:payload].to_json
    event.processed_at = Time.current
  end
end

puts "  ✅ Created #{WebhookEvent.count} webhook events"

# Create revenue snapshots for analytics
puts "\n📈 Creating revenue snapshots..."

# Skip revenue snapshots for now - comment out to avoid hanging
=begin
# Generate monthly revenue snapshots for the past 6 months
6.downto(0) do |months_ago|
  snapshot_date = months_ago.months.ago.beginning_of_month

  # Calculate metrics based on existing data
  active_subscriptions = Subscription.where(status: 'active')
    .joins(:plan)
    .where('subscriptions.created_at <= ?', snapshot_date.end_of_month)

  mrr = active_subscriptions.sum('plans.price_cents')
  arr = mrr * 12

  # Count active customers (accounts with active subscriptions)
  active_customers = Account.joins(:subscription)
    .where(subscriptions: { status: 'active' })
    .where('accounts.created_at <= ?', snapshot_date.end_of_month)
    .count

  # Calculate churn (simplified for demo)
  churned_customers = months_ago == 0 ? 0 : rand(0..2)
  new_customers = months_ago == 0 ? 2 : rand(1..4)

  # Count by plan
  plan_distribution = active_subscriptions
    .group('plans.name')
    .count

  RevenueSnapshot.find_or_create_by!(
    snapshot_date: snapshot_date
  ) do |snapshot|
    snapshot.mrr_cents = mrr
    snapshot.arr_cents = arr
    snapshot.active_customers = active_customers
    snapshot.churned_customers = churned_customers
    snapshot.new_customers = new_customers
    snapshot.growth_rate = months_ago == 6 ? 0 : rand(5..15) / 100.0
    snapshot.metadata = {
      plan_distribution: plan_distribution,
      snapshot_type: 'monthly',
      test_data: true
    }
  end
end
=end

puts "  ⏭️  Skipped revenue snapshots (commented out)"

# Create additional sample pages for testing
puts "\n📄 Creating additional sample pages..."

# Get admin user for page authorship
admin_user = User.find_by(email: 'admin@powernode.org')

additional_pages = [
  {
    title: 'Getting Started Guide',
    slug: 'getting-started',
    content: '# Getting Started

Welcome to Powernode! Here\'s how to get started with your subscription business.

## Step 1: Set Up Your Account

Configure your company profile and billing information.

## Step 2: Create Subscription Plans

Define your pricing tiers and features for each plan.

## Step 3: Configure Payment Gateways

Connect your Stripe or PayPal account to start accepting payments.

## Step 4: Invite Your Team

Add team members and assign appropriate roles.

## Step 5: Launch Your Subscription Business

Start accepting customers and watch your business grow!',
    status: 'published'
  },
  {
    title: 'API Documentation',
    slug: 'api-docs',
    content: '# API Documentation

Complete REST API reference for developers.

## Authentication

All API requests require authentication using JWT tokens.

## Endpoints

### Subscriptions

- GET /api/v1/subscriptions - List all subscriptions
- POST /api/v1/subscriptions - Create a subscription
- GET /api/v1/subscriptions/:id - Get subscription details
- PATCH /api/v1/subscriptions/:id - Update subscription
- DELETE /api/v1/subscriptions/:id - Cancel subscription

### Customers

- GET /api/v1/customers - List all customers
- POST /api/v1/customers - Create a customer
- GET /api/v1/customers/:id - Get customer details',
    status: 'published'
  },
  {
    title: 'Billing FAQ',
    slug: 'billing-faq',
    content: '# Billing FAQ

Common questions about billing and subscriptions.

## How does billing work?

Subscriptions are billed automatically on a recurring basis according to your chosen plan.

## What payment methods are accepted?

We accept all major credit cards through Stripe and PayPal.

## Can I change my plan?

Yes, you can upgrade or downgrade your plan at any time. Changes take effect at the next billing cycle.

## What happens if a payment fails?

We\'ll retry the payment and notify you. After multiple failures, the subscription may be suspended.

## How do I cancel my subscription?

You can cancel your subscription at any time from your account settings.',
    status: 'published'
  }
]

additional_pages.each do |page_data|
  Page.find_or_create_by!(slug: page_data[:slug]) do |page|
    page.title = page_data[:title]
    page.content = page_data[:content]
    page.status = page_data[:status]
    page.author_id = admin_user.id
    page.published_at = Time.current
  end
end

puts "  ✅ Created #{additional_pages.count} additional pages"

# Create account delegations for testing
puts "\n🤝 Creating account delegations..."

# Get admin account
admin_account = Account.find_by(name: 'Powernode Administration')

# Create delegated admin users
delegated_users = []
3.times do |i|
  user = User.find_or_create_by!(email: "delegated.admin#{i+1}@powernode.dev") do |u|
    u.account = admin_account
    u.first_name = "Delegated"
    u.last_name = "Admin#{i+1}"
    u.password = 'DelegateSecure456!@#$%'
    u.password_confirmation = 'DelegateSecure456!@#$%'
    u.status = 'active'
    u.role = 'admin'
    u.email_verified = true
    u.email_verified_at = Time.current
  end
  delegated_users << user
end

# Create delegations for enterprise accounts
enterprise_accounts = Account.joins(:subscription)
  .where(subscriptions: { plan: enterprise_plan })
  .limit(2)

enterprise_accounts.each_with_index do |account, index|
  break if index >= delegated_users.count

  delegated_user = delegated_users[index]
  delegator = account.users.where(role: 'owner').first

  if delegator
    role_name = index == 0 ? 'Admin' : 'Member'
    role = Role.find_by(name: role_name)

    Account::Delegation.find_or_create_by!(
      account: account,
      delegated_user: delegated_user,
      delegated_by: delegator
    ) do |delegation|
      delegation.role = role
      delegation.status = 'active'
      delegation.expires_at = (index + 3).months.from_now
      delegation.notes = "Test delegation for #{account.name}"
    end
  end
end

puts "  ✅ Created #{Account::Delegation.count} account delegations"

# Create sample gateway configurations (demo values only)
# Only set if no configuration exists yet - preserve real credentials
puts "\n🔧 Creating sample gateway configurations..."

gateway_configs_created = 0

# Helper to set gateway config only if not already configured
def set_gateway_config_if_blank(provider, key, demo_value)
  existing = GatewayConfiguration.find_by(provider: provider, key_name: key)
  if existing
    puts "  ⏭️  #{provider}/#{key} already configured - preserving existing value"
    return false
  end
  GatewayConfiguration.set_config(provider, key, demo_value)
  true
end

gateway_configs_created += 1 if set_gateway_config_if_blank('stripe', 'publishable_key', 'pk_test_demo_key_for_development')
gateway_configs_created += 1 if set_gateway_config_if_blank('stripe', 'secret_key', 'sk_test_demo_secret_for_development')
gateway_configs_created += 1 if set_gateway_config_if_blank('stripe', 'webhook_endpoint_secret', 'whsec_demo_endpoint_secret')
gateway_configs_created += 1 if set_gateway_config_if_blank('stripe', 'webhook_tolerance', '300')

gateway_configs_created += 1 if set_gateway_config_if_blank('paypal', 'client_id', 'demo_paypal_client_id')
gateway_configs_created += 1 if set_gateway_config_if_blank('paypal', 'client_secret', 'demo_paypal_client_secret')
gateway_configs_created += 1 if set_gateway_config_if_blank('paypal', 'webhook_id', 'demo_webhook_id')
gateway_configs_created += 1 if set_gateway_config_if_blank('paypal', 'mode', 'sandbox')

puts "  ✅ #{gateway_configs_created} new gateway configurations created (#{GatewayConfiguration.count} total)"

# Create admin worker for API testing
admin_worker = Worker.find_or_create_by!(name: 'Test API Worker') do |worker|
  worker.description = 'Test worker for API development'
  worker.permissions = 'standard'
  worker.status = 'active'
  worker.account = admin_account
  worker.token = Worker.generate_secure_token
end

puts "\n🔑 Created Test API Worker:"
puts "  - Name: #{admin_worker.name}"
puts "  - Token: #{admin_worker.token}"

# Final summary
puts "\n📊 Test Data Summary:"
puts "  - Total Accounts: #{Account.count}"
puts "  - Total Users: #{User.count}"
puts "  - Total Subscriptions: #{Subscription.count}"
puts "  - Total Invoices: #{Invoice.count}"
puts "  - Total Payments: #{Payment.count}"
puts "  - Total Webhook Events: #{WebhookEvent.count}"
puts "  - Total Revenue Snapshots: #{RevenueSnapshot.count}"
puts "  - Total Pages: #{Page.count}"
puts "  - Total Payment Methods: #{PaymentMethod.count}"
puts "  - Total Account Delegations: #{Account::Delegation.count}"
puts "  - Total Gateway Configurations: #{GatewayConfiguration.count}"
puts "  - Total Workers: #{Worker.count}"

puts "\n✅ Test data loaded successfully!"
