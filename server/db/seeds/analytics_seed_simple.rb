# Simple Analytics Test Data Seeder
# This creates revenue snapshots for analytics charts (global data only)

puts "🔄 Seeding Analytics Data (Simple Version)..."

# Generate additional account-specific snapshots for accounts that have subscriptions
accounts_with_subscription = Account.joins(:subscription).distinct

puts "📈 Creating account-specific snapshots for #{accounts_with_subscription.count} accounts..."

accounts_with_subscription.find_each do |account|
  puts "  Processing account: #{account.name}"
  
  # Generate snapshots for this account over the last 12 months
  start_date = 12.months.ago.beginning_of_month
  end_date = Date.current.end_of_month
  
  current_date = start_date
  account_snapshots_created = 0
  
  # Base metrics for this account (smaller scale)
  account_base_mrr = rand(500_00..3000_00) # $500-3000 per account
  account_base_customers = 1 # Since it's has_one :subscription
  
  while current_date <= end_date
    months_passed = ((current_date - start_date) / 30.days).to_i
    
    # Account-specific growth simulation
    growth_multiplier = 1 + (months_passed * 0.05) + (Math.sin(months_passed * Math::PI / 6) * 0.1)
    randomness = 0.8 + (rand * 0.4) # Between 0.8 and 1.2
    
    mrr_cents = (account_base_mrr * growth_multiplier * randomness).to_i
    active_subs = 1 # Always 1 since account has_one subscription
    
    # Simulate some churn/reactivation (but always end up with 1 subscription)
    if rand < 0.1 && months_passed > 3 # 10% chance of churn/reactivation
      new_subs = 1
      churned_subs = 1
    else
      new_subs = 0
      churned_subs = 0
    end
    
    customer_churn_rate = churned_subs > 0 ? 100.0 : 0.0 # All or nothing for single subscription
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
    else
      puts "    ❌ Failed to create snapshot for #{current_date}: #{snapshot.errors.full_messages.join(', ')}"
    end
    
    current_date += 1.month
  end
  
  puts "    ✅ Created #{account_snapshots_created} snapshots"
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