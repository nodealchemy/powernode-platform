# Analytics Test Data Seeder
# This creates revenue snapshots for analytics charts

puts "🔄 Seeding Analytics Data..."

# Ensure we have plans and subscriptions first
if Plan.count == 0
  puts "❌ No plans found. Run basic seed first: rails db:seed"
  exit
end

if Subscription.count == 0
  puts "❌ No subscriptions found. Run basic seed first: rails db:seed"
  exit
end

# Create global analytics service instance
analytics_service = RevenueAnalyticsService.new

# Generate revenue snapshots for the last 24 months
start_date = 24.months.ago.beginning_of_month
end_date = Date.current.end_of_month

puts "📊 Generating revenue snapshots from #{start_date} to #{end_date}..."

current_date = start_date
monthly_snapshots_created = 0

# Base metrics for growth simulation
base_mrr = 5000_00  # $5,000 in cents
base_customers = 50

while current_date <= end_date
  # Simulate realistic growth patterns
  months_passed = ((current_date - start_date) / 30.days).to_i
  
  # Growth simulation with some seasonality and randomness
  growth_multiplier = 1 + (months_passed * 0.08) + (Math.sin(months_passed * Math::PI / 6) * 0.1)
  randomness = 0.8 + (rand * 0.4) # Between 0.8 and 1.2
  
  # Calculate realistic metrics
  mrr_cents = (base_mrr * growth_multiplier * randomness).to_i
  active_subs = [1, (base_customers * growth_multiplier * randomness).to_i].max
  
  # Simulate monthly subscription changes
  if months_passed > 0
    new_subs = [0, (active_subs * 0.15 * randomness).to_i].max # 15% new growth
    churned_subs = [0, (active_subs * 0.05 * randomness).to_i].max # 5% churn
  else
    new_subs = active_subs  # First month starts with all subscriptions
    churned_subs = 0
  end
  
  # Calculate churn and growth rates
  customer_churn_rate = active_subs > 0 ? (churned_subs.to_f / active_subs * 100) : 0.0
  growth_rate = months_passed > 0 ? ((growth_multiplier - 1) * 100) : 0.0
  
  # Create or update revenue snapshot
  snapshot = RevenueSnapshot.find_or_initialize_by(
    account: nil, # Global snapshot
    snapshot_date: current_date
  )
  
  snapshot.assign_attributes(
    mrr_cents: mrr_cents,
    arr_cents: mrr_cents * 12,
    active_subscriptions: active_subs,
    new_subscriptions: new_subs,
    churned_subscriptions: churned_subs,
    currency: "USD",
    metadata: {
      total_customers_count: active_subs, # Simplified: 1 customer per subscription
      new_customers_count: new_subs,
      churned_customers_count: churned_subs,
      customer_churn_rate: customer_churn_rate.round(2),
      revenue_churn_rate: customer_churn_rate.round(2), # Simplified
      growth_rate: growth_rate.round(2)
    }
  )
  
  if snapshot.save
    monthly_snapshots_created += 1
    if monthly_snapshots_created % 6 == 0
      print "."
    end
  else
    puts "\n❌ Failed to create snapshot for #{current_date}: #{snapshot.errors.full_messages.join(', ')}"
  end
  
  current_date += 1.month
end

puts "\n✅ Created #{monthly_snapshots_created} monthly revenue snapshots"

# Create account-specific snapshots for accounts with subscriptions
accounts_with_subscriptions = Account.joins(:subscriptions).distinct

accounts_with_subscriptions.find_each do |account|
  puts "📈 Creating snapshots for account: #{account.name}"
  
  account_analytics = RevenueAnalyticsService.new(account: account)
  account_snapshots_created = 0
  
  # Generate snapshots for this account
  current_date = start_date
  account_base_mrr = 1000_00 * rand(2..8) # Random base MRR between $2K-8K
  account_base_customers = account.subscriptions.count
  
  while current_date <= end_date
    months_passed = ((current_date - start_date) / 30.days).to_i
    
    # Account-specific growth (smaller and more variable)
    growth_multiplier = 1 + (months_passed * 0.06) + (Math.sin(months_passed * Math::PI / 4) * 0.15)
    randomness = 0.7 + (rand * 0.6) # More variability for individual accounts
    
    mrr_cents = (account_base_mrr * growth_multiplier * randomness).to_i
    active_subs = [1, (account_base_customers * growth_multiplier * randomness).to_i].max
    
    new_subs = months_passed > 0 ? [0, (active_subs * 0.1 * randomness).to_i].max : active_subs
    churned_subs = months_passed > 0 ? [0, (active_subs * 0.08 * randomness).to_i].max : 0
    
    customer_churn_rate = active_subs > 0 ? (churned_subs.to_f / active_subs * 100) : 0.0
    growth_rate = months_passed > 0 ? ((growth_multiplier - 1) * 100) : 0.0
    
    snapshot = RevenueSnapshot.find_or_initialize_by(
      account: account,
      snapshot_date: current_date
    )
    
    snapshot.assign_attributes(
      mrr_cents: mrr_cents,
      arr_cents: mrr_cents * 12,
      active_subscriptions: active_subs,
      new_subscriptions: new_subs,
      churned_subscriptions: churned_subs,
      currency: "USD",
      metadata: {
        total_customers_count: active_subs,
        new_customers_count: new_subs,
        churned_customers_count: churned_subs,
        customer_churn_rate: customer_churn_rate.round(2),
        revenue_churn_rate: customer_churn_rate.round(2),
        growth_rate: growth_rate.round(2)
      }
    )
    
    if snapshot.save
      account_snapshots_created += 1
    end
    
    current_date += 1.month
  end
  
  puts "  ✅ Created #{account_snapshots_created} snapshots for #{account.name}"
end

# Summary
total_snapshots = RevenueSnapshot.count
global_snapshots = RevenueSnapshot.global.count
account_snapshots = RevenueSnapshot.where.not(account: nil).count

puts "\n📊 Analytics Seeding Complete!"
puts "   Global snapshots: #{global_snapshots}"
puts "   Account-specific snapshots: #{account_snapshots}"
puts "   Total snapshots: #{total_snapshots}"

# Show sample data
latest_global = RevenueSnapshot.global.order(:snapshot_date).last
if latest_global
  puts "\n📈 Latest Global Metrics:"
  puts "   MRR: $#{latest_global.mrr.to_f}"
  puts "   Active Subscriptions: #{latest_global.active_subscriptions}"
  puts "   Growth Rate: #{latest_global.growth_rate_percentage}%"
  puts "   Customer Churn: #{latest_global.customer_churn_rate_percentage}%"
end

puts "\n🎯 Analytics charts should now display data!"
puts "   Navigate to /analytics in your application to see the results."