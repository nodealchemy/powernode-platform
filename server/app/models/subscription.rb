# frozen_string_literal: true

class Subscription < ApplicationRecord
  include AASM

  # Associations
  belongs_to :account
  belongs_to :plan
  has_many :invoices, dependent: :destroy
  has_many :payments, through: :invoices

  # Validations
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :account, presence: true, uniqueness: { message: "can only have one subscription" }
  validates :stripe_subscription_id, uniqueness: { allow_nil: true }
  validates :paypal_subscription_id, uniqueness: { allow_nil: true }

  # Note: metadata is a native JSON column - no serialization needed in Rails 8

  # Scopes
  scope :active, -> { where(status: [ "trialing", "active" ]) }
  scope :inactive, -> { where(status: [ "canceled", "unpaid", "incomplete_expired" ]) }
  scope :past_due, -> { where(status: "past_due") }
  scope :trialing, -> { where(status: "trialing") }
  scope :expiring_soon, -> { where(current_period_end: Time.current..7.days.from_now) }
  scope :trial_ending_soon, -> { where(trial_end: Time.current..3.days.from_now) }

  # Callbacks
  before_create :set_trial_period
  after_initialize :set_defaults
  after_create :schedule_lifecycle_events, :log_subscription_creation
  after_update :handle_status_changes, if: :saved_change_to_status?
  after_update :log_subscription_changes, if: :saved_changes?

  # State Machine
  aasm column: :status do
    state :trialing, initial: true
    state :active
    state :past_due
    state :canceled
    state :unpaid
    state :incomplete
    state :incomplete_expired
    state :paused

    event :activate do
      transitions from: [ :trialing, :past_due, :unpaid, :paused ], to: :active
      after do
        update_period_dates
      end
    end

    event :mark_past_due do
      transitions from: [ :active, :trialing ], to: :past_due
    end

    event :cancel do
      transitions from: [ :trialing, :active, :past_due, :unpaid, :paused ], to: :canceled
      after do
        self.canceled_at = Time.current
        self.ended_at = Time.current unless ended_at.present?
      end
    end

    event :mark_unpaid do
      transitions from: [ :active, :past_due ], to: :unpaid
    end

    event :pause do
      transitions from: [ :active, :trialing ], to: :paused
    end

    event :resume do
      transitions from: :paused, to: :active
    end

    event :expire do
      transitions from: [ :incomplete, :past_due, :unpaid ], to: :incomplete_expired
      after do
        self.ended_at = Time.current
      end
    end
  end

  # Instance methods
  def active?
    %w[trialing active].include?(status)
  end

  def on_trial?
    status == "trialing" && trial_end.present? && trial_end > Time.current
  end

  def trial_ended?
    trial_end.present? && trial_end <= Time.current
  end

  def days_until_trial_ends
    return 0 unless on_trial?
    ((trial_end - Time.current) / 1.day).ceil
  end

  def days_until_period_ends
    return 0 unless current_period_end
    ((current_period_end - Time.current) / 1.day).ceil
  end

  def total_price
    plan.price_cents * quantity
  end

  def next_billing_date
    return trial_end if on_trial?
    current_period_end
  end

  def can_be_canceled?
    !%w[canceled incomplete_expired].include?(status)
  end

  def using_stripe?
    stripe_subscription_id.present?
  end

  def using_paypal?
    paypal_subscription_id.present?
  end

  def payment_provider
    return "stripe" if using_stripe?
    return "paypal" if using_paypal?
    "none"
  end

  def needs_payment_retry?
    past_due? || unpaid?
  end

  def in_grace_period?
    return false unless past_due?
    grace_end = metadata['payment_method_grace_period_end']
    grace_end.present? && Time.parse(grace_end) > Time.current
  end

  def overdue_days
    return 0 unless current_period_end && current_period_end < Time.current
    ((Time.current - current_period_end) / 1.day).ceil
  end

  def schedule_billing_automation(delay: 0)
    return if canceled? || incomplete_expired?
    WorkerJobService.enqueue_billing_automation(id, delay: delay.seconds)
  end

  private

  def set_trial_period
    if plan.trial_days > 0 && trial_end.blank?
      self.trial_end = plan.trial_days.days.from_now
      self.current_period_start = Time.current
      self.current_period_end = trial_end
    end
  end

  def set_defaults
    self.metadata ||= {}
  end

  def update_period_dates
    now = Time.current
    self.current_period_start = now

    case plan.billing_cycle
    when "monthly"
      self.current_period_end = now + 1.month
    when "quarterly"
      self.current_period_end = now + 3.months
    when "yearly"
      self.current_period_end = now + 1.year
    end
  end

  def schedule_lifecycle_events
    return unless persisted?
    
    # Schedule trial ending reminders if on trial
    if trialing? && trial_end.present?
      schedule_trial_reminders
    end
    
    # Schedule renewal reminders if active
    if active? && current_period_end.present?
      schedule_renewal_reminders
    end
  end

  def handle_status_changes
    case status
    when 'active'
      handle_activation
    when 'past_due'
      handle_past_due
    when 'unpaid'
      handle_unpaid_status
    when 'canceled'
      handle_cancellation
    end
  end

  def schedule_trial_reminders
    return unless trial_end.present? && trial_end > Time.current

    # Schedule reminders for 7, 3, and 1 days before trial ends
    [7, 3, 1].each do |days_before|
      reminder_time = trial_end - days_before.days
      next if reminder_time <= Time.current

      begin
        WorkerJobService.enqueue_subscription_lifecycle(
          'trial_ending_reminder',
          id,
          run_at: reminder_time,
          days_remaining: days_before
        )
        Rails.logger.info "Scheduled trial reminder for subscription #{id} at #{reminder_time}"
      rescue WorkerJobService::WorkerServiceError => e
        Rails.logger.error "Failed to schedule trial reminder: #{e.message}"
      end
    end

    # Schedule trial conversion check
    begin
      WorkerJobService.enqueue_subscription_lifecycle(
        'trial_ended',
        id,
        run_at: trial_end
      )
      Rails.logger.info "Scheduled trial end processing for subscription #{id} at #{trial_end}"
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to schedule trial end: #{e.message}"
    end
  end

  def schedule_renewal_reminders
    return unless current_period_end.present? && current_period_end > Time.current

    # Schedule reminders for 7, 3, and 1 days before renewal
    [7, 3, 1].each do |days_before|
      reminder_time = current_period_end - days_before.days
      next if reminder_time <= Time.current

      begin
        WorkerJobService.enqueue_subscription_lifecycle(
          'renewal_reminder',
          id,
          run_at: reminder_time,
          days_remaining: days_before
        )
        Rails.logger.info "Scheduled renewal reminder for subscription #{id} at #{reminder_time}"
      rescue WorkerJobService::WorkerServiceError => e
        Rails.logger.error "Failed to schedule renewal reminder: #{e.message}"
      end
    end

    # Schedule billing automation at period end
    begin
      WorkerJobService.enqueue_billing_automation(id, delay: (current_period_end - Time.current).to_i)
      Rails.logger.info "Scheduled billing automation for subscription #{id} at #{current_period_end}"
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to schedule billing automation: #{e.message}"
    end
  end

  def handle_activation
    Rails.logger.info "Subscription #{id} activated"
    
    # Schedule renewal reminders
    schedule_renewal_reminders if current_period_end.present?
    
    # Clear any dunning metadata
    if metadata['dunning_level'].present?
      self.update_columns(
        metadata: metadata.except('dunning_level', 'last_dunning_attempt')
      )
    end
  end

  def handle_past_due
    Rails.logger.info "Subscription #{id} marked as past due"
    
    # Update metadata with dunning information
    self.update_columns(
      metadata: metadata.merge(
        'dunning_level' => 'soft_dunning',
        'past_due_since' => Time.current.iso8601
      )
    )
  end

  def handle_unpaid_status
    Rails.logger.info "Subscription #{id} marked as unpaid"
    
    # Update metadata
    self.update_columns(
      metadata: metadata.merge(
        'dunning_level' => 'final_dunning',
        'unpaid_since' => Time.current.iso8601
      )
    )
  end

  def handle_cancellation
    Rails.logger.info "Subscription #{id} canceled"
    
    # Clear any scheduled jobs related to this subscription
    # Note: In a real implementation, you'd want to cancel specific scheduled jobs
    # This is a simplified approach
  end

  def log_subscription_creation
    AuditLog.log_action(
      action: "create",
      resource: self,
      account: account,
      new_values: subscription_audit_values,
      source: "system",
      metadata: {
        event_type: "subscription_created",
        plan_name: plan.name,
        trial_end: trial_end&.iso8601
      }
    )
  end

  def log_subscription_changes
    return unless persisted? && saved_changes.present?
    
    # Track significant changes
    significant_changes = saved_changes.slice(
      'status', 'plan_id', 'quantity', 'current_period_start', 
      'current_period_end', 'trial_end', 'canceled_at', 'ended_at'
    )
    
    return if significant_changes.empty?
    
    old_values = {}
    new_values = {}
    
    significant_changes.each do |field, (old_val, new_val)|
      case field
      when 'plan_id'
        old_plan = old_val ? Plan.find_by(id: old_val) : nil
        new_plan = new_val ? Plan.find_by(id: new_val) : nil
        old_values['plan'] = old_plan&.name
        new_values['plan'] = new_plan&.name
        old_values['plan_price'] = old_plan&.price_cents
        new_values['plan_price'] = new_plan&.price_cents
      when 'current_period_start', 'current_period_end', 'trial_end', 'canceled_at', 'ended_at'
        old_values[field] = old_val&.iso8601
        new_values[field] = new_val&.iso8601
      else
        old_values[field] = old_val
        new_values[field] = new_val
      end
    end
    
    # Determine the primary action type
    action_type = if saved_changes.key?('plan_id')
                    'subscription_change'
                  elsif saved_changes.key?('status')
                    'subscription_change'
                  elsif saved_changes.key?('quantity')
                    'subscription_change'
                  else
                    'update'
                  end
    
    AuditLog.log_action(
      action: action_type,
      resource: self,
      account: account,
      old_values: old_values,
      new_values: new_values,
      source: "system",
      metadata: {
        event_type: determine_event_type(saved_changes),
        changes_count: significant_changes.keys.count,
        changed_fields: significant_changes.keys
      }
    )
  end

  def subscription_audit_values
    {
      status: status,
      plan: plan.name,
      plan_price: plan.price_cents,
      quantity: quantity,
      trial_end: trial_end&.iso8601,
      current_period_start: current_period_start&.iso8601,
      current_period_end: current_period_end&.iso8601
    }
  end

  def determine_event_type(changes)
    if changes.key?('status')
      old_status, new_status = changes['status']
      case new_status
      when 'active'
        old_status == 'trialing' ? 'trial_converted' : 'subscription_activated'
      when 'canceled'
        'subscription_canceled'
      when 'past_due'
        'payment_failed'
      when 'trialing'
        'trial_started'
      else
        'status_changed'
      end
    elsif changes.key?('plan_id')
      'plan_changed'
    elsif changes.key?('quantity')
      'quantity_changed'
    else
      'subscription_updated'
    end
  end
end