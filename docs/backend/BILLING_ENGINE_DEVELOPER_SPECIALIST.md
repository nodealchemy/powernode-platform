---
Last Updated: 2026-02-28
Platform Version: 0.3.0
---

# Billing Engine Developer Specialist Guide

## Role & Responsibilities

The Billing Engine Developer specializes in subscription lifecycle management, automated billing, proration calculations, and dunning systems for Powernode's subscription platform.

### Core Responsibilities
- Implementing subscription lifecycle management
- Building automated renewal systems  
- Handling proration calculations
- Developing dunning and recovery systems
- Creating invoicing and PDF generation

### Key Focus Areas
- Complex billing logic and calculations
- Sidekiq background jobs for automated processes
- Automated retry mechanisms and failure handling
- Revenue recognition and accounting integration
- Subscription plan changes and upgrades

## Billing Engine Architecture Standards

### 1. Subscription Lifecycle Management (MANDATORY)

#### Subscription State Machine
```ruby
# app/models/subscription.rb
class Subscription < ApplicationRecord
  include AASM
  
  belongs_to :account
  belongs_to :plan
  has_many :payments, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :subscription_changes, dependent: :destroy
  
  monetize :amount_cents
  
  aasm column: :status do
    state :pending, initial: true
    state :active
    state :past_due
    state :cancelled
    state :suspended
    state :expired
    
    event :activate do
      transitions from: [:pending, :past_due, :suspended], to: :active
      after do
        update_billing_cycle
        schedule_next_billing
      end
    end
    
    event :mark_past_due do
      transitions from: :active, to: :past_due
      after do
        start_dunning_process
      end
    end
    
    event :cancel do
      transitions from: [:active, :past_due, :suspended], to: :cancelled
      after do
        process_cancellation
        cancel_scheduled_billing
      end
    end
    
    event :suspend do
      transitions from: [:active, :past_due], to: :suspended
      after do
        suspend_services
        cancel_scheduled_billing
      end
    end
    
    event :expire do
      transitions from: [:active, :past_due, :suspended], to: :expired
      after do
        process_expiration
      end
    end
  end
  
  scope :active, -> { where(status: 'active') }
  scope :renewable, -> { where(status: ['active', 'past_due']) }
  scope :due_for_renewal, -> { where('next_billing_date <= ?', Time.current) }
  
  def days_until_renewal
    return 0 unless next_billing_date
    ((next_billing_date - Time.current) / 1.day).ceil
  end
  
  def current_billing_cycle
    {
      start: current_period_start,
      end: current_period_end,
      days_total: (current_period_end - current_period_start).to_i / 1.day,
      days_remaining: [(current_period_end - Time.current).to_i / 1.day, 0].max
    }
  end
  
  def prorated_amount_for_upgrade(new_plan)
    return new_plan.price_cents if current_period_start == Time.current.beginning_of_day
    
    ProrationCalculatorService.call(
      subscription: self,
      new_plan: new_plan,
      change_date: Time.current
    ).result
  end
  
  private
  
  def update_billing_cycle
    self.current_period_start = Time.current
    self.current_period_end = calculate_period_end
    self.next_billing_date = current_period_end
    save!
  end
  
  def calculate_period_end
    case plan.billing_interval
    when 'month'
      current_period_start + 1.month
    when 'year'
      current_period_start + 1.year
    when 'week'
      current_period_start + 1.week
    else
      raise "Invalid billing interval: #{plan.billing_interval}"
    end
  end
  
  def schedule_next_billing
    WorkerJobService.enqueue_billing_job('subscription_renewal', {
      subscription_id: id,
      scheduled_for: next_billing_date.iso8601
    })
  end
  
  def cancel_scheduled_billing
    # Cancel any pending renewal jobs
    WorkerJobService.cancel_billing_job('subscription_renewal', subscription_id: id)
  end
  
  def start_dunning_process
    WorkerJobService.enqueue_billing_job('dunning_process_start', {
      subscription_id: id,
      past_due_date: Time.current.iso8601
    })
  end
  
  def process_cancellation
    self.cancelled_at = Time.current
    self.cancellation_reason = 'user_requested'
    save!
    
    # Process any final billing
    WorkerJobService.enqueue_billing_job('final_billing', { subscription_id: id })
  end
  
  def suspend_services
    # Disable account access, API keys, etc.
    account.update!(status: 'suspended', suspended_at: Time.current)
  end
  
  def process_expiration
    self.expired_at = Time.current
    save!
    
    # Cleanup and archival
    WorkerJobService.enqueue_billing_job('subscription_cleanup', { subscription_id: id })
  end
end
```

#### Subscription Service Layer
```ruby
# app/services/subscription_lifecycle_service.rb
class SubscriptionLifecycleService < BaseService
  attribute :subscription, Subscription
  attribute :action, String
  attribute :metadata, Hash, default: {}
  
  VALID_ACTIONS = %w[activate cancel suspend reactivate upgrade downgrade].freeze
  
  validates :subscription, :action, presence: true
  validates :action, inclusion: { in: VALID_ACTIONS }
  
  def call
    return failure("Invalid parameters", errors.full_messages) unless valid?
    
    begin
      case action
      when 'activate'
        activate_subscription
      when 'cancel'
        cancel_subscription
      when 'suspend'
        suspend_subscription
      when 'reactivate'
        reactivate_subscription
      when 'upgrade', 'downgrade'
        change_subscription_plan
      end
    rescue StandardError => e
      Rails.logger.error "Subscription lifecycle action failed: #{e.message}"
      failure("Lifecycle action failed", { error: e.message })
    end
  end
  
  private
  
  def activate_subscription
    if subscription.may_activate?
      subscription.activate!
      
      # Create activation invoice if needed
      create_activation_invoice if should_invoice_activation?
      
      # Send welcome notification
      WorkerJobService.enqueue_billing_job('subscription_activated_notification', {
        subscription_id: subscription.id
      })
      
      success({ subscription: subscription_data })
    else
      failure("Cannot activate subscription in current state: #{subscription.status}")
    end
  end
  
  def cancel_subscription
    cancellation_type = metadata[:cancellation_type] || 'immediate'
    
    case cancellation_type
    when 'immediate'
      immediate_cancellation
    when 'end_of_period'
      end_of_period_cancellation
    else
      failure("Invalid cancellation type: #{cancellation_type}")
    end
  end
  
  def immediate_cancellation
    if subscription.may_cancel?
      # Calculate any refunds due
      refund_amount = calculate_refund_amount
      
      subscription.cancel!
      
      # Process refund if applicable
      if refund_amount > 0
        WorkerJobService.enqueue_billing_job('process_refund', {
          subscription_id: subscription.id,
          refund_amount_cents: refund_amount
        })
      end
      
      success({ 
        subscription: subscription_data,
        refund_amount_cents: refund_amount
      })
    else
      failure("Cannot cancel subscription in current state: #{subscription.status}")
    end
  end
  
  def end_of_period_cancellation
    subscription.update!(
      cancellation_scheduled: true,
      cancellation_date: subscription.current_period_end,
      cancellation_reason: metadata[:reason] || 'user_requested'
    )
    
    # Schedule cancellation
    WorkerJobService.enqueue_billing_job('scheduled_cancellation', {
      subscription_id: subscription.id,
      scheduled_for: subscription.current_period_end.iso8601
    })
    
    success({ 
      subscription: subscription_data,
      cancellation_scheduled_for: subscription.current_period_end.iso8601
    })
  end
  
  def change_subscription_plan
    new_plan_id = metadata[:new_plan_id]
    new_plan = Plan.find(new_plan_id)
    
    change_service = SubscriptionPlanChangeService.call(
      subscription: subscription,
      new_plan: new_plan,
      change_type: action,
      effective_date: metadata[:effective_date] || Time.current
    )
    
    if change_service.success?
      success(change_service.data)
    else
      failure(change_service.error, change_service.details)
    end
  end
  
  def should_invoice_activation?
    !subscription.trial? && subscription.plan.price_cents > 0
  end
  
  def create_activation_invoice
    InvoiceGenerationService.call(
      subscription: subscription,
      invoice_type: 'activation',
      due_date: Time.current
    )
  end
  
  def calculate_refund_amount
    return 0 unless subscription.active?
    
    days_remaining = subscription.current_billing_cycle[:days_remaining]
    total_days = subscription.current_billing_cycle[:days_total]
    
    return 0 if days_remaining <= 0 || total_days <= 0
    
    prorated_refund = (subscription.amount_cents * days_remaining / total_days).round
    [prorated_refund, 0].max
  end
  
  def subscription_data
    {
      id: subscription.id,
      status: subscription.status,
      current_period: {
        start: subscription.current_period_start&.iso8601,
        end: subscription.current_period_end&.iso8601
      },
      next_billing_date: subscription.next_billing_date&.iso8601,
      updated_at: subscription.updated_at.iso8601
    }
  end
end
```

### 2. Automated Renewal System (MANDATORY)

#### Renewal Processing Service
```ruby
# app/services/subscription_renewal_service.rb
class SubscriptionRenewalService < BaseService
  attribute :subscription, Subscription
  attribute :retry_attempt, Integer, default: 0
  
  MAX_RETRY_ATTEMPTS = 3
  
  def call
    return failure("Subscription not renewable") unless subscription.renewable?
    return failure("Max retry attempts exceeded") if retry_attempt > MAX_RETRY_ATTEMPTS
    
    begin
      ActiveRecord::Base.transaction do
        process_renewal
      end
    rescue PaymentProcessingError => e
      handle_payment_failure(e)
    rescue StandardError => e
      Rails.logger.error "Subscription renewal failed: #{e.message}"
      failure("Renewal processing failed", { error: e.message })
    end
  end
  
  private
  
  def process_renewal
    # Generate invoice for upcoming period
    invoice = create_renewal_invoice
    
    # Process payment
    payment_result = process_renewal_payment(invoice)
    
    if payment_result.success?
      # Update subscription for next period
      advance_billing_period
      
      # Schedule next renewal
      schedule_next_renewal
      
      # Send success notification
      send_renewal_success_notification
      
      success({
        subscription: subscription_data,
        invoice: invoice_data(invoice),
        payment: payment_result.data
      })
    else
      handle_payment_failure(payment_result)
    end
  end
  
  def create_renewal_invoice
    invoice_service = InvoiceGenerationService.call(
      subscription: subscription,
      invoice_type: 'renewal',
      billing_period_start: subscription.current_period_end,
      billing_period_end: calculate_next_period_end,
      due_date: subscription.current_period_end
    )
    
    unless invoice_service.success?
      raise StandardError, "Failed to create renewal invoice: #{invoice_service.error}"
    end
    
    invoice_service.data[:invoice]
  end
  
  def process_renewal_payment(invoice)
    payment_method = subscription.account.default_payment_method
    
    unless payment_method
      raise PaymentProcessingError, "No payment method available"
    end
    
    PaymentProcessingService.call(
      invoice: invoice,
      payment_method: payment_method,
      description: "Subscription renewal for #{subscription.plan.name}"
    )
  end
  
  def advance_billing_period
    subscription.update!(
      current_period_start: subscription.current_period_end,
      current_period_end: calculate_next_period_end,
      next_billing_date: calculate_next_period_end,
      renewed_at: Time.current,
      renewal_count: subscription.renewal_count + 1
    )
  end
  
  def calculate_next_period_end
    case subscription.plan.billing_interval
    when 'month'
      subscription.current_period_end + 1.month
    when 'year'
      subscription.current_period_end + 1.year
    when 'week'
      subscription.current_period_end + 1.week
    end
  end
  
  def schedule_next_renewal
    WorkerJobService.enqueue_billing_job('subscription_renewal', {
      subscription_id: subscription.id,
      scheduled_for: subscription.next_billing_date.iso8601
    })
  end
  
  def handle_payment_failure(error)
    if retry_attempt < MAX_RETRY_ATTEMPTS
      schedule_retry
      subscription.mark_past_due! if subscription.may_mark_past_due?
      
      failure("Payment failed, retry scheduled", {
        error: error.message,
        retry_attempt: retry_attempt + 1,
        next_retry: calculate_retry_time
      })
    else
      # Max retries exceeded - start dunning process
      subscription.mark_past_due! if subscription.may_mark_past_due?
      
      WorkerJobService.enqueue_billing_job('dunning_process_start', {
        subscription_id: subscription.id,
        final_payment_failure: true
      })
      
      failure("Payment permanently failed", {
        error: error.message,
        dunning_process_started: true
      })
    end
  end
  
  def schedule_retry
    WorkerJobService.enqueue_billing_job('subscription_renewal', {
      subscription_id: subscription.id,
      retry_attempt: retry_attempt + 1,
      scheduled_for: calculate_retry_time.iso8601
    })
  end
  
  def calculate_retry_time
    # Exponential backoff: 1 day, 3 days, 7 days
    retry_delays = [1.day, 3.days, 7.days]
    retry_delays[retry_attempt] || 7.days
    
    Time.current + retry_delays[retry_attempt]
  end
  
  def send_renewal_success_notification
    WorkerJobService.enqueue_billing_job('subscription_renewed_notification', {
      subscription_id: subscription.id,
      renewal_date: Time.current.iso8601
    })
  end
  
  class PaymentProcessingError < StandardError; end
end
```

### 3. Proration Calculation System (MANDATORY)

#### Proration Calculator Service
```ruby
# app/services/proration_calculator_service.rb
class ProrationCalculatorService < BaseService
  attribute :subscription, Subscription
  attribute :new_plan, Plan  
  attribute :change_date, DateTime, default: -> { Time.current }
  attribute :proration_type, String, default: 'immediate'
  
  PRORATION_TYPES = %w[immediate end_of_period].freeze
  
  validates :subscription, :new_plan, :change_date, presence: true
  validates :proration_type, inclusion: { in: PRORATION_TYPES }
  
  def call
    return failure("Invalid parameters", errors.full_messages) unless valid?
    
    begin
      calculate_proration
    rescue StandardError => e
      Rails.logger.error "Proration calculation failed: #{e.message}"
      failure("Calculation failed", { error: e.message })
    end
  end
  
  private
  
  def calculate_proration
    case proration_type
    when 'immediate'
      calculate_immediate_proration
    when 'end_of_period'
      calculate_end_of_period_change
    end
  end
  
  def calculate_immediate_proration
    current_plan = subscription.plan
    
    # Calculate unused time credit from current plan
    unused_credit = calculate_unused_credit(current_plan)
    
    # Calculate prorated charge for new plan
    prorated_charge = calculate_prorated_charge(new_plan)
    
    # Net amount due
    net_amount = prorated_charge - unused_credit
    
    success({
      proration_details: {
        current_plan: plan_summary(current_plan),
        new_plan: plan_summary(new_plan),
        change_date: change_date.iso8601,
        billing_period: {
          start: subscription.current_period_start.iso8601,
          end: subscription.current_period_end.iso8601,
          days_total: total_days_in_period,
          days_used: days_used_in_period,
          days_remaining: days_remaining_in_period
        },
        unused_credit_cents: unused_credit,
        prorated_charge_cents: prorated_charge,
        net_amount_cents: net_amount,
        immediate_charge: net_amount > 0,
        credit_applied: net_amount < 0 ? net_amount.abs : 0
      }
    })
  end
  
  def calculate_end_of_period_change
    # No proration - change happens at end of current period
    success({
      proration_details: {
        current_plan: plan_summary(subscription.plan),
        new_plan: plan_summary(new_plan),
        change_date: subscription.current_period_end.iso8601,
        billing_period: {
          start: subscription.current_period_start.iso8601,
          end: subscription.current_period_end.iso8601,
          days_remaining: days_remaining_in_period
        },
        unused_credit_cents: 0,
        prorated_charge_cents: 0,
        net_amount_cents: 0,
        scheduled_change: true,
        effective_date: subscription.current_period_end.iso8601,
        next_billing_amount_cents: new_plan.price_cents
      }
    })
  end
  
  def calculate_unused_credit(plan)
    return 0 if days_remaining_in_period <= 0
    
    daily_rate = plan.price_cents.to_f / total_days_in_period
    (daily_rate * days_remaining_in_period).round
  end
  
  def calculate_prorated_charge(plan)
    return 0 if days_remaining_in_period <= 0
    
    daily_rate = plan.price_cents.to_f / total_days_in_period
    (daily_rate * days_remaining_in_period).round
  end
  
  def total_days_in_period
    @total_days ||= (subscription.current_period_end - subscription.current_period_start).to_i / 1.day
  end
  
  def days_used_in_period
    @days_used ||= [((change_date - subscription.current_period_start).to_i / 1.day), 0].max
  end
  
  def days_remaining_in_period
    @days_remaining ||= [total_days_in_period - days_used_in_period, 0].max
  end
  
  def plan_summary(plan)
    {
      id: plan.id,
      name: plan.name,
      price_cents: plan.price_cents,
      billing_interval: plan.billing_interval
    }
  end
end
```

#### Plan Change Service
```ruby
# app/services/subscription_plan_change_service.rb
class SubscriptionPlanChangeService < BaseService
  attribute :subscription, Subscription
  attribute :new_plan, Plan
  attribute :change_type, String  # 'upgrade', 'downgrade'
  attribute :effective_date, DateTime, default: -> { Time.current }
  attribute :proration_type, String, default: 'immediate'
  
  validates :subscription, :new_plan, :change_type, presence: true
  validates :change_type, inclusion: { in: %w[upgrade downgrade] }
  
  def call
    return failure("Invalid parameters", errors.full_messages) unless valid?
    return failure("Cannot change to same plan") if subscription.plan_id == new_plan.id
    
    begin
      ActiveRecord::Base.transaction do
        process_plan_change
      end
    rescue StandardError => e
      Rails.logger.error "Plan change failed: #{e.message}"
      failure("Plan change failed", { error: e.message })
    end
  end
  
  private
  
  def process_plan_change
    # Calculate proration
    proration_result = ProrationCalculatorService.call(
      subscription: subscription,
      new_plan: new_plan,
      change_date: effective_date,
      proration_type: proration_type
    )
    
    unless proration_result.success?
      raise StandardError, "Proration calculation failed: #{proration_result.error}"
    end
    
    proration_details = proration_result.data[:proration_details]
    
    if proration_type == 'immediate'
      execute_immediate_change(proration_details)
    else
      schedule_end_of_period_change(proration_details)
    end
  end
  
  def execute_immediate_change(proration_details)
    # Create subscription change record
    change_record = create_subscription_change_record(proration_details)
    
    # Process proration billing if needed
    if proration_details[:net_amount_cents] > 0
      process_proration_billing(proration_details, change_record)
    elsif proration_details[:net_amount_cents] < 0
      apply_account_credit(proration_details[:credit_applied], change_record)
    end
    
    # Update subscription
    update_subscription_for_new_plan(proration_details)
    
    # Send notification
    send_plan_change_notification(change_record)
    
    success({
      subscription: subscription_data,
      change_record: change_record_data(change_record),
      proration_details: proration_details
    })
  end
  
  def schedule_end_of_period_change(proration_details)
    # Create scheduled change record
    change_record = create_subscription_change_record(proration_details, scheduled: true)
    
    # Schedule the change
    WorkerJobService.enqueue_billing_job('scheduled_plan_change', {
      subscription_id: subscription.id,
      new_plan_id: new_plan.id,
      change_record_id: change_record.id,
      scheduled_for: proration_details[:effective_date]
    })
    
    success({
      subscription: subscription_data,
      change_record: change_record_data(change_record),
      proration_details: proration_details,
      scheduled_change: true
    })
  end
  
  def create_subscription_change_record(proration_details, scheduled: false)
    subscription.subscription_changes.create!(
      from_plan: subscription.plan,
      to_plan: new_plan,
      change_type: change_type,
      effective_date: scheduled ? proration_details[:effective_date] : Time.current,
      proration_details: proration_details,
      status: scheduled ? 'scheduled' : 'completed',
      net_amount_cents: proration_details[:net_amount_cents]
    )
  end
  
  def process_proration_billing(proration_details, change_record)
    # Create proration invoice
    invoice = Invoice.create!(
      subscription: subscription,
      invoice_type: 'proration',
      total_cents: proration_details[:net_amount_cents],
      due_date: Time.current,
      description: "Plan change from #{subscription.plan.name} to #{new_plan.name}",
      metadata: { change_record_id: change_record.id }
    )
    
    # Add line items
    invoice.line_items.create!([
      {
        description: "Credit for unused time on #{subscription.plan.name}",
        amount_cents: -proration_details[:unused_credit_cents],
        quantity: 1
      },
      {
        description: "Prorated charge for #{new_plan.name}",
        amount_cents: proration_details[:prorated_charge_cents],
        quantity: 1
      }
    ])
    
    # Process payment immediately
    WorkerJobService.enqueue_billing_job('process_proration_payment', {
      invoice_id: invoice.id,
      change_record_id: change_record.id
    })
  end
  
  def apply_account_credit(credit_amount, change_record)
    subscription.account.increment!(:account_credit_cents, credit_amount)
    
    # Log credit application
    subscription.account.account_credits.create!(
      amount_cents: credit_amount,
      source: 'plan_change',
      description: "Credit from plan change",
      reference_id: change_record.id
    )
  end
  
  def update_subscription_for_new_plan(proration_details)
    subscription.update!(
      plan: new_plan,
      amount_cents: new_plan.price_cents,
      last_plan_change_at: Time.current
    )
  end
  
  def send_plan_change_notification(change_record)
    WorkerJobService.enqueue_billing_job('plan_change_notification', {
      subscription_id: subscription.id,
      change_record_id: change_record.id,
      change_type: change_type
    })
  end
  
  def subscription_data
    {
      id: subscription.id,
      plan: {
        id: subscription.plan.id,
        name: subscription.plan.name,
        price_cents: subscription.plan.price_cents
      },
      status: subscription.status,
      updated_at: subscription.updated_at.iso8601
    }
  end
  
  def change_record_data(change_record)
    {
      id: change_record.id,
      change_type: change_record.change_type,
      effective_date: change_record.effective_date.iso8601,
      status: change_record.status,
      net_amount_cents: change_record.net_amount_cents
    }
  end
end
```

### 4. Dunning and Recovery System (MANDATORY)

#### Dunning Process Service
```ruby
# app/services/dunning_process_service.rb
class DunningProcessService < BaseService
  attribute :subscription, Subscription
  attribute :dunning_stage, Integer, default: 1
  attribute :final_attempt, Boolean, default: false
  
  DUNNING_STAGES = {
    1 => { days: 1, action: 'gentle_reminder' },
    2 => { days: 3, action: 'payment_reminder' }, 
    3 => { days: 7, action: 'urgent_notice' },
    4 => { days: 14, action: 'final_warning' },
    5 => { days: 21, action: 'suspension_notice' },
    6 => { days: 30, action: 'cancellation_notice' }
  }.freeze
  
  def call
    return failure("Subscription not in dunning-eligible state") unless subscription.past_due?
    return failure("Invalid dunning stage") unless DUNNING_STAGES.key?(dunning_stage)
    
    begin
      process_dunning_stage
    rescue StandardError => e
      Rails.logger.error "Dunning process failed: #{e.message}"
      failure("Dunning process failed", { error: e.message })
    end
  end
  
  private
  
  def process_dunning_stage
    stage_config = DUNNING_STAGES[dunning_stage]
    
    # Update dunning status
    update_dunning_status(stage_config)
    
    # Execute stage action
    case stage_config[:action]
    when 'gentle_reminder'
      send_gentle_reminder
    when 'payment_reminder'
      send_payment_reminder_and_retry
    when 'urgent_notice'
      send_urgent_notice_and_retry
    when 'final_warning'
      send_final_warning_and_retry
    when 'suspension_notice'
      suspend_subscription
    when 'cancellation_notice'
      cancel_subscription
    end
    
    # Schedule next stage if not final
    schedule_next_stage unless final_stage?
    
    success({
      subscription: subscription_data,
      dunning_stage: dunning_stage,
      action_taken: stage_config[:action],
      next_action_date: next_stage_date&.iso8601
    })
  end
  
  def update_dunning_status(stage_config)
    subscription.update!(
      dunning_stage: dunning_stage,
      last_dunning_action: stage_config[:action],
      last_dunning_date: Time.current
    )
  end
  
  def send_gentle_reminder
    WorkerJobService.enqueue_billing_job('dunning_gentle_reminder', {
      subscription_id: subscription.id,
      stage: dunning_stage
    })
  end
  
  def send_payment_reminder_and_retry
    # Send notification
    WorkerJobService.enqueue_billing_job('dunning_payment_reminder', {
      subscription_id: subscription.id,
      stage: dunning_stage
    })
    
    # Attempt payment retry
    retry_payment
  end
  
  def send_urgent_notice_and_retry
    # Send urgent notice
    WorkerJobService.enqueue_billing_job('dunning_urgent_notice', {
      subscription_id: subscription.id,
      stage: dunning_stage,
      suspension_warning: true
    })
    
    # Final payment retry attempt
    retry_payment
  end
  
  def send_final_warning_and_retry
    # Send final warning
    WorkerJobService.enqueue_billing_job('dunning_final_warning', {
      subscription_id: subscription.id,
      stage: dunning_stage,
      final_attempt: true
    })
    
    # Last chance payment retry
    retry_payment
  end
  
  def suspend_subscription
    if subscription.may_suspend?
      subscription.suspend!
      
      # Notify of suspension
      WorkerJobService.enqueue_billing_job('subscription_suspended_notification', {
        subscription_id: subscription.id,
        reason: 'payment_failure',
        dunning_stage: dunning_stage
      })
    end
  end
  
  def cancel_subscription
    if subscription.may_cancel?
      subscription.cancel!
      
      # Final cancellation notice
      WorkerJobService.enqueue_billing_job('subscription_cancelled_notification', {
        subscription_id: subscription.id,
        reason: 'payment_failure',
        final_dunning_stage: true
      })
      
      # Archive subscription data
      WorkerJobService.enqueue_billing_job('archive_cancelled_subscription', {
        subscription_id: subscription.id
      })
    end
  end
  
  def retry_payment
    # Attempt to process payment again
    WorkerJobService.enqueue_billing_job('dunning_payment_retry', {
      subscription_id: subscription.id,
      dunning_stage: dunning_stage,
      retry_type: 'dunning'
    })
  end
  
  def schedule_next_stage
    next_stage = dunning_stage + 1
    return unless DUNNING_STAGES.key?(next_stage)
    
    WorkerJobService.enqueue_billing_job('dunning_process_continue', {
      subscription_id: subscription.id,
      dunning_stage: next_stage,
      scheduled_for: next_stage_date.iso8601
    })
  end
  
  def next_stage_date
    return nil if final_stage?
    
    next_stage = dunning_stage + 1
    return nil unless DUNNING_STAGES.key?(next_stage)
    
    Time.current + DUNNING_STAGES[next_stage][:days].days
  end
  
  def final_stage?
    dunning_stage >= DUNNING_STAGES.keys.max
  end
  
  def subscription_data
    {
      id: subscription.id,
      status: subscription.status,
      dunning_stage: subscription.dunning_stage,
      last_dunning_action: subscription.last_dunning_action,
      past_due_since: subscription.past_due_since&.iso8601
    }
  end
end
```

### 5. Invoice Generation System (MANDATORY)

#### Invoice Generation Service
```ruby
# app/services/invoice_generation_service.rb
class InvoiceGenerationService < BaseService
  attribute :subscription, Subscription
  attribute :invoice_type, String, default: 'recurring'
  attribute :billing_period_start, DateTime
  attribute :billing_period_end, DateTime
  attribute :due_date, DateTime
  attribute :line_items, Array, default: []
  
  INVOICE_TYPES = %w[recurring activation proration one_time].freeze
  
  validates :subscription, :invoice_type, presence: true
  validates :invoice_type, inclusion: { in: INVOICE_TYPES }
  
  def call
    return failure("Invalid parameters", errors.full_messages) unless valid?
    
    begin
      ActiveRecord::Base.transaction do
        create_invoice
      end
    rescue StandardError => e
      Rails.logger.error "Invoice generation failed: #{e.message}"
      failure("Invoice generation failed", { error: e.message })
    end
  end
  
  private
  
  def create_invoice
    invoice = build_invoice
    
    # Add line items based on invoice type
    add_line_items_to_invoice(invoice)
    
    # Calculate totals
    calculate_invoice_totals(invoice)
    
    # Generate invoice number
    generate_invoice_number(invoice)
    
    # Save invoice
    invoice.save!
    
    # Generate PDF if needed
    schedule_pdf_generation(invoice) if should_generate_pdf?
    
    # Send invoice notification
    send_invoice_notification(invoice)
    
    success({
      invoice: invoice_data(invoice),
      line_items: invoice.line_items.map { |li| line_item_data(li) }
    })
  end
  
  def build_invoice
    Invoice.new(
      subscription: subscription,
      account: subscription.account,
      invoice_type: invoice_type,
      billing_period_start: billing_period_start || subscription.current_period_start,
      billing_period_end: billing_period_end || subscription.current_period_end,
      due_date: due_date || calculate_due_date,
      currency: subscription.plan.currency,
      status: 'draft',
      issued_at: Time.current
    )
  end
  
  def add_line_items_to_invoice(invoice)
    case invoice_type
    when 'recurring'
      add_recurring_line_items(invoice)
    when 'activation'
      add_activation_line_items(invoice)
    when 'proration'
      add_proration_line_items(invoice)
    when 'one_time'
      add_custom_line_items(invoice)
    end
  end
  
  def add_recurring_line_items(invoice)
    plan = subscription.plan
    
    invoice.line_items.build(
      description: "#{plan.name} - #{format_billing_period(invoice)}",
      quantity: 1,
      unit_price_cents: plan.price_cents,
      amount_cents: plan.price_cents,
      plan_id: plan.id
    )
    
    # Add any usage-based charges
    add_usage_charges(invoice) if plan.has_usage_billing?
    
    # Add any applicable taxes
    add_tax_line_items(invoice)
    
    # Apply any discounts
    apply_discounts(invoice)
  end
  
  def add_activation_line_items(invoice)
    plan = subscription.plan
    
    # Pro-rated charge for activation
    activation_amount = calculate_activation_amount
    
    invoice.line_items.build(
      description: "#{plan.name} - Activation (#{format_billing_period(invoice)})",
      quantity: 1,
      unit_price_cents: activation_amount,
      amount_cents: activation_amount,
      plan_id: plan.id
    )
    
    # Setup fees if applicable
    if plan.setup_fee_cents > 0
      invoice.line_items.build(
        description: "Setup Fee - #{plan.name}",
        quantity: 1,
        unit_price_cents: plan.setup_fee_cents,
        amount_cents: plan.setup_fee_cents
      )
    end
    
    add_tax_line_items(invoice)
  end
  
  def add_proration_line_items(invoice)
    # Custom line items should be provided for proration invoices
    line_items.each do |item|
      invoice.line_items.build(
        description: item[:description],
        quantity: item[:quantity] || 1,
        unit_price_cents: item[:unit_price_cents],
        amount_cents: item[:amount_cents] || (item[:quantity] * item[:unit_price_cents])
      )
    end
    
    add_tax_line_items(invoice)
  end
  
  def add_usage_charges(invoice)
    # Calculate usage for the billing period
    usage_service = UsageCalculationService.call(
      subscription: subscription,
      period_start: invoice.billing_period_start,
      period_end: invoice.billing_period_end
    )
    
    if usage_service.success? && usage_service.data[:total_usage_cents] > 0
      invoice.line_items.build(
        description: "Usage charges - #{format_billing_period(invoice)}",
        quantity: usage_service.data[:total_units],
        unit_price_cents: usage_service.data[:unit_price_cents],
        amount_cents: usage_service.data[:total_usage_cents],
        usage_data: usage_service.data[:usage_breakdown]
      )
    end
  end
  
  def add_tax_line_items(invoice)
    # Calculate applicable taxes based on account location
    tax_service = TaxCalculationService.call(
      account: subscription.account,
      invoice: invoice
    )
    
    if tax_service.success? && tax_service.data[:total_tax_cents] > 0
      tax_service.data[:tax_breakdown].each do |tax_item|
        invoice.line_items.build(
          description: tax_item[:description],
          quantity: 1,
          unit_price_cents: tax_item[:amount_cents],
          amount_cents: tax_item[:amount_cents],
          line_item_type: 'tax',
          tax_rate: tax_item[:rate]
        )
      end
    end
  end
  
  def apply_discounts(invoice)
    # Apply any active discounts or coupons
    discount_service = DiscountApplicationService.call(
      subscription: subscription,
      invoice: invoice
    )
    
    if discount_service.success? && discount_service.data[:total_discount_cents] > 0
      invoice.line_items.build(
        description: discount_service.data[:description],
        quantity: 1,
        unit_price_cents: -discount_service.data[:total_discount_cents],
        amount_cents: -discount_service.data[:total_discount_cents],
        line_item_type: 'discount'
      )
    end
  end
  
  def calculate_invoice_totals(invoice)
    subtotal = invoice.line_items.where.not(line_item_type: 'tax').sum(:amount_cents)
    tax_total = invoice.line_items.where(line_item_type: 'tax').sum(:amount_cents)
    total = subtotal + tax_total
    
    invoice.assign_attributes(
      subtotal_cents: subtotal,
      tax_cents: tax_total,
      total_cents: total
    )
  end
  
  def generate_invoice_number(invoice)
    prefix = case invoice_type
             when 'recurring' then 'INV'
             when 'activation' then 'ACT'
             when 'proration' then 'PRO'
             when 'one_time' then 'OT'
             end
    
    sequence = Invoice.where(
      "invoice_number LIKE ?", 
      "#{prefix}-#{Date.current.strftime('%Y%m')}-%"
    ).count + 1
    
    invoice.invoice_number = "#{prefix}-#{Date.current.strftime('%Y%m')}-#{sequence.to_s.rjust(4, '0')}"
  end
  
  def calculate_due_date
    # Default due date is immediate for recurring, 30 days for others
    case invoice_type
    when 'recurring'
      Time.current
    else
      30.days.from_now
    end
  end
  
  def calculate_activation_amount
    return subscription.plan.price_cents if billing_period_start.nil?
    
    # Prorate based on activation date within billing period
    total_days = (billing_period_end - billing_period_start).to_i / 1.day
    remaining_days = (billing_period_end - Time.current).to_i / 1.day
    
    return 0 if remaining_days <= 0
    
    daily_rate = subscription.plan.price_cents.to_f / total_days
    (daily_rate * remaining_days).round
  end
  
  def format_billing_period(invoice)
    start_date = invoice.billing_period_start.strftime('%b %d, %Y')
    end_date = invoice.billing_period_end.strftime('%b %d, %Y')
    "#{start_date} - #{end_date}"
  end
  
  def should_generate_pdf?
    invoice_type != 'proration' || subscription.account.pdf_invoices_enabled?
  end
  
  def schedule_pdf_generation(invoice)
    WorkerJobService.enqueue_billing_job('generate_invoice_pdf', {
      invoice_id: invoice.id
    })
  end
  
  def send_invoice_notification(invoice)
    WorkerJobService.enqueue_billing_job('send_invoice_notification', {
      invoice_id: invoice.id,
      invoice_type: invoice_type
    })
  end
  
  def invoice_data(invoice)
    {
      id: invoice.id,
      invoice_number: invoice.invoice_number,
      status: invoice.status,
      total_cents: invoice.total_cents,
      due_date: invoice.due_date.iso8601,
      created_at: invoice.created_at.iso8601
    }
  end
  
  def line_item_data(line_item)
    {
      description: line_item.description,
      quantity: line_item.quantity,
      unit_price_cents: line_item.unit_price_cents,
      amount_cents: line_item.amount_cents
    }
  end
end
```

## Development Commands

### Billing Engine Management
```bash
# Generate billing models and services  
rails generate model SubscriptionChange subscription:references from_plan:references to_plan:references
rails generate model Invoice subscription:references account:references
rails generate model InvoiceLineItem invoice:references

# Run billing-related migrations
rails db:migrate

# Test billing processes in console
rails console
> subscription = Subscription.first
> SubscriptionLifecycleService.call(subscription: subscription, action: 'activate')
> ProrationCalculatorService.call(subscription: subscription, new_plan: Plan.last)

# Monitor background billing jobs
bundle exec sidekiq -C config/sidekiq.yml -e development
```

### Testing Billing Logic
```bash
# Run billing-specific tests
bundle exec rspec spec/services/billing/
bundle exec rspec spec/models/subscription_spec.rb
bundle exec rspec spec/jobs/billing/

# Test renewal processes
rails runner "SubscriptionRenewalService.call(subscription: Subscription.due_for_renewal.first)"

# Test dunning processes  
rails runner "DunningProcessService.call(subscription: Subscription.past_due.first)"
```

## Integration Points

### Billing Engine Developer Coordinates With:
- **Payment Integration Specialist**: Payment processing, webhook handling
- **Background Job Engineer**: Job scheduling, retry mechanisms
- **Data Modeler**: Subscription and billing data models
- **API Developer**: Billing endpoint implementation
- **Notification Engineer**: Billing notifications, dunning emails

## Quick Reference

### Billing Process Flow
1. **Subscription Creation** → Activation invoice → Payment processing
2. **Renewal Processing** → Generate invoice → Process payment → Update billing cycle
3. **Plan Changes** → Calculate proration → Process billing → Update subscription
4. **Failed Payments** → Dunning process → Retries → Suspension/Cancellation
5. **Invoice Generation** → Line items → Totals → PDF → Notifications

### Key Service Classes
- `SubscriptionLifecycleService` - Manage subscription states
- `SubscriptionRenewalService` - Handle automated renewals  
- `ProrationCalculatorService` - Calculate plan change billing
- `DunningProcessService` - Handle failed payment recovery
- `InvoiceGenerationService` - Create and format invoices

**ALWAYS REFERENCE ../TODO.md FOR CURRENT TASKS AND PRIORITIES**