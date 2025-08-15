namespace :billing do
  desc "Run billing automation for all subscriptions"
  task automation: :environment do
    puts "Starting billing automation cycle..."
    
    begin
      BillingAutomationJob.perform_now
      puts "Billing automation completed successfully"
    rescue => e
      puts "Billing automation failed: #{e.message}"
      puts e.backtrace.join("\n") if ENV['VERBOSE']
    end
  end

  desc "Run billing automation for specific subscription"
  task :automation_for, [:subscription_id] => :environment do |t, args|
    subscription_id = args[:subscription_id]
    
    unless subscription_id
      puts "Usage: rake billing:automation_for[subscription_id]"
      exit 1
    end

    puts "Running billing automation for subscription #{subscription_id}..."
    
    begin
      BillingAutomationJob.perform_now(subscription_id)
      puts "Billing automation completed for subscription #{subscription_id}"
    rescue => e
      puts "Billing automation failed: #{e.message}"
      puts e.backtrace.join("\n") if ENV['VERBOSE']
    end
  end

  desc "Retry failed payment"
  task :retry_payment, [:payment_id, :retry_attempt] => :environment do |t, args|
    payment_id = args[:payment_id]
    retry_attempt = (args[:retry_attempt] || 1).to_i
    
    unless payment_id
      puts "Usage: rake billing:retry_payment[payment_id,retry_attempt]"
      exit 1
    end

    puts "Retrying payment #{payment_id} (attempt #{retry_attempt})..."
    
    begin
      PaymentRetryJob.perform_now(payment_id, retry_attempt)
      puts "Payment retry completed for payment #{payment_id}"
    rescue => e
      puts "Payment retry failed: #{e.message}"
      puts e.backtrace.join("\n") if ENV['VERBOSE']
    end
  end

  desc "Run billing scheduler"
  task scheduler: :environment do
    date = ENV['DATE'] ? Date.parse(ENV['DATE']) : Date.current
    puts "Running billing scheduler for #{date}..."
    
    begin
      BillingSchedulerJob.perform_now(date)
      puts "Billing scheduler completed successfully"
    rescue => e
      puts "Billing scheduler failed: #{e.message}"
      puts e.backtrace.join("\n") if ENV['VERBOSE']
    end
  end

  desc "Run billing cleanup"
  task cleanup: :environment do
    puts "Starting billing cleanup..."
    
    begin
      BillingCleanupJob.perform_now
      puts "Billing cleanup completed successfully"
    rescue => e
      puts "Billing cleanup failed: #{e.message}"
      puts e.backtrace.join("\n") if ENV['VERBOSE']
    end
  end

  desc "Show billing health report"
  task health: :environment do
    puts "Billing System Health Report"
    puts "=" * 40
    
    report = BillingAutomation.get_billing_health_report
    
    if report
      puts "Report generated: #{report[:timestamp]}"
      puts
      puts "Payment Success Rate: #{(report[:payment_success_rate] * 100).round(2)}%"
      puts
      puts "Subscription Health:"
      health = report[:subscription_health]
      puts "  Total: #{health[:total]}"
      puts "  Active: #{health[:active]}"
      puts "  Past Due: #{health[:past_due]}"
      puts "  Churn Rate: #{(health[:churn_rate] * 100).round(2)}%"
      puts
      puts "Revenue Metrics:"
      revenue = report[:revenue_metrics]
      puts "  Current MRR: $#{revenue[:current_mrr_cents] / 100.0}"
      puts "  Last Month Revenue: $#{revenue[:last_month_revenue_cents] / 100.0}"
      puts
      puts "Failed Payments Analysis:"
      failed = report[:failed_payment_analysis]
      puts "  Total Failed: #{failed[:total_failed]}"
      puts "  By Gateway: #{failed[:failure_by_gateway]}"
      puts "  Top Failure Reasons: #{failed[:failure_reasons].first(3).to_h}"
    else
      puts "No health report available. Run billing cleanup to generate one."
    end
  end

  desc "Show subscription metrics"
  task metrics: :environment do
    puts "Subscription Metrics"
    puts "=" * 30
    
    metrics = BillingAutomation.get_subscription_metrics
    
    if metrics
      puts "Last updated: #{metrics[:updated_at]}"
      puts
      puts "Active Subscriptions by Plan:"
      metrics[:active_by_plan].each do |plan, count|
        puts "  #{plan}: #{count}"
      end
      puts
      puts "MRR by Plan:"
      metrics[:mrr_by_plan].each do |plan, mrr_cents|
        puts "  #{plan}: $#{mrr_cents / 100.0}"
      end
      puts
      puts "Trial Conversion:"
      conv = metrics[:trial_conversions]
      puts "  Total Trials Ended: #{conv[:total_trials_ended]}"
      puts "  Converted to Paid: #{conv[:converted_to_paid]}"
      puts "  Conversion Rate: #{conv[:conversion_rate]}%"
    else
      puts "No metrics available. Run billing cleanup to generate them."
    end
  end

  desc "List overdue subscriptions"
  task overdue: :environment do
    puts "Overdue Subscriptions"
    puts "=" * 30
    
    overdue_subs = Subscription.joins(:account)
                              .where(status: ['active', 'trialing', 'past_due'])
                              .where('current_period_end < ?', Time.current)
                              .includes(:account, :plan)
                              .order(:current_period_end)
    
    if overdue_subs.any?
      overdue_subs.each do |sub|
        overdue_days = ((Time.current - sub.current_period_end) / 1.day).ceil
        puts "#{sub.id}: #{sub.account.name} (#{sub.plan.name}) - #{overdue_days} days overdue"
      end
    else
      puts "No overdue subscriptions found."
    end
  end

  desc "Force process overdue subscriptions"
  task process_overdue: :environment do
    puts "Processing overdue subscriptions..."
    
    overdue_subs = Subscription.joins(:account)
                              .where(status: ['active', 'trialing', 'past_due'])
                              .where('current_period_end < ?', Time.current)
                              .where(accounts: { status: 'active' })
    
    count = overdue_subs.count
    puts "Found #{count} overdue subscriptions to process"
    
    overdue_subs.find_each do |subscription|
      puts "Processing subscription #{subscription.id}..."
      BillingAutomationJob.perform_later(subscription.id)
    end
    
    puts "Queued #{count} billing automation jobs"
  end

  desc "Test billing automation with dry run"
  task dry_run: :environment do
    puts "Billing Automation Dry Run"
    puts "=" * 35
    
    # Find subscriptions that would be processed
    subscriptions_due = Subscription.joins(:account)
                                   .where(status: ['active', 'trialing', 'past_due'])
                                   .where('current_period_end <= ?', Time.current.end_of_day)
                                   .where(accounts: { status: 'active' })
                                   .includes(:plan, :account, account: :users)

    puts "Subscriptions due for processing: #{subscriptions_due.count}"
    
    subscriptions_due.each do |sub|
      payment_method = sub.account.payment_methods.default.first
      payment_status = payment_method ? "✓ Has payment method" : "✗ No payment method"
      
      puts "  #{sub.id}: #{sub.account.name} (#{sub.plan.name}) - #{sub.status} - #{payment_status}"
    end
    
    # Check trials ending
    trials_ending = Subscription.joins(:account)
                               .where(status: 'trialing')
                               .where('trial_end BETWEEN ? AND ?', Time.current, 7.days.from_now)
                               .includes(:plan, :account)

    puts "\nTrials ending in next 7 days: #{trials_ending.count}"
    
    trials_ending.each do |sub|
      days_left = ((sub.trial_end - Time.current) / 1.day).ceil
      payment_method = sub.account.payment_methods.default.first
      payment_status = payment_method ? "✓ Has payment method" : "✗ No payment method"
      
      puts "  #{sub.id}: #{sub.account.name} (#{sub.plan.name}) - #{days_left} days left - #{payment_status}"
    end
  end
end