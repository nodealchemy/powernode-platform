# frozen_string_literal: true

module Ai
  class RoiMetric < ApplicationRecord
    include Auditable

    # ==========================================================================
    # CONSTANTS
    # ==========================================================================

    METRIC_TYPES = %w[workflow agent provider team account_total department].freeze
    PERIOD_TYPES = %w[daily weekly monthly quarterly yearly].freeze

    # Default hourly rate for time savings calculations
    DEFAULT_HOURLY_RATE = 75.0

    # ==========================================================================
    # ASSOCIATIONS
    # ==========================================================================

    belongs_to :account
    belongs_to :attributable, polymorphic: true, optional: true
    has_many :cost_attributions, class_name: "Ai::CostAttribution", foreign_key: "roi_metric_id", dependent: :destroy

    # ==========================================================================
    # VALIDATIONS
    # ==========================================================================

    validates :metric_type, presence: true, inclusion: { in: METRIC_TYPES }
    validates :period_type, presence: true, inclusion: { in: PERIOD_TYPES }
    validates :period_date, presence: true
    validates :ai_cost_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :total_cost_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :time_saved_hours, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validate :unique_period_metric

    # ==========================================================================
    # SCOPES
    # ==========================================================================

    scope :for_account, ->(account) { where(account: account) }
    scope :for_type, ->(type) { where(metric_type: type) }
    scope :for_period_type, ->(type) { where(period_type: type) }
    scope :for_date_range, ->(start_date, end_date) { where(period_date: start_date..end_date) }
    scope :daily, -> { where(period_type: "daily") }
    scope :weekly, -> { where(period_type: "weekly") }
    scope :monthly, -> { where(period_type: "monthly") }
    scope :recent, ->(days = 30) { where("period_date >= ?", days.days.ago.to_date) }
    scope :account_totals, -> { where(metric_type: "account_total") }
    scope :with_positive_roi, -> { where("roi_percentage > 0") }

    # ==========================================================================
    # CALLBACKS
    # ==========================================================================

    before_validation :calculate_derived_metrics
    before_save :recalculate_totals

    # ==========================================================================
    # INSTANCE METHODS
    # ==========================================================================

    # Calculate ROI percentage
    def calculate_roi
      return 0.0 if total_cost_usd.zero?

      ((total_value_usd - total_cost_usd) / total_cost_usd * 100).round(2)
    end

    # Calculate net benefit
    def calculate_net_benefit
      total_value_usd - total_cost_usd
    end

    # Get time savings in monetary terms
    def time_saved_monetary_value(hourly_rate: DEFAULT_HOURLY_RATE)
      time_saved_hours * hourly_rate
    end

    # Check if ROI is positive
    def positive_roi?
      roi_percentage.present? && roi_percentage > 0
    end

    # Get break-even analysis
    def break_even_analysis
      return nil if total_cost_usd.zero?

      {
        break_even_tasks: total_cost_usd.positive? ? (total_cost_usd / (value_per_task_usd || 1)).ceil : 0,
        current_tasks: tasks_completed,
        tasks_to_break_even: [ 0, (total_cost_usd / (value_per_task_usd || 1)).ceil - tasks_completed ].max,
        is_profitable: positive_roi?
      }
    end

    # Get efficiency metrics
    def efficiency_metrics
      {
        automation_rate: tasks_completed > 0 ? (tasks_automated.to_f / tasks_completed * 100).round(2) : 0,
        error_rate: tasks_completed > 0 ? ((tasks_completed - errors_prevented).to_f / tasks_completed * 100).round(2) : 0,
        manual_intervention_rate: tasks_automated > 0 ? (manual_interventions.to_f / tasks_automated * 100).round(2) : 0,
        efficiency_gain: efficiency_gain_percentage || 0
      }
    end

    # Get comprehensive summary
    def summary
      {
        id: id,
        period: {
          type: period_type,
          date: period_date,
          formatted: format_period
        },
        costs: {
          ai: ai_cost_usd,
          infrastructure: infrastructure_cost_usd,
          total: total_cost_usd,
          per_task: cost_per_task_usd
        },
        value: {
          time_saved_hours: time_saved_hours,
          time_saved_value: time_saved_value_usd,
          error_reduction: error_reduction_value_usd,
          throughput: throughput_value_usd,
          total: total_value_usd,
          per_task: value_per_task_usd
        },
        roi: {
          percentage: roi_percentage,
          net_benefit: net_benefit_usd,
          is_positive: positive_roi?
        },
        baseline_comparison: {
          baseline_cost: baseline_cost_usd,
          baseline_time: baseline_time_hours,
          efficiency_gain: efficiency_gain_percentage
        },
        activity: {
          tasks_completed: tasks_completed,
          tasks_automated: tasks_automated,
          errors_prevented: errors_prevented,
          manual_interventions: manual_interventions
        },
        quality: {
          accuracy_rate: accuracy_rate,
          satisfaction_score: customer_satisfaction_score
        }
      }
    end

    # Format period for display
    def format_period
      case period_type
      when "daily"
        period_date.strftime("%B %d, %Y")
      when "weekly"
        "Week of #{period_date.strftime('%B %d, %Y')}"
      when "monthly"
        period_date.strftime("%B %Y")
      when "quarterly"
        quarter = ((period_date.month - 1) / 3) + 1
        "Q#{quarter} #{period_date.year}"
      when "yearly"
        period_date.year.to_s
      else
        period_date.to_s
      end
    end

    # Class method: Calculate ROI for an account over a period
    def self.calculate_for_account(account, period_type: "daily", period_date: Date.current)
      # Find or initialize the metric
      metric = find_or_initialize_by(
        account: account,
        metric_type: "account_total",
        period_type: period_type,
        period_date: period_date
      )

      # Calculate values from executions
      date_range = date_range_for_period(period_type, period_date)

      # Get AI costs from executions
      workflow_costs = Ai::WorkflowRun
                         .joins(:workflow)
                         .where(ai_workflows: { account_id: account.id })
                         .where(created_at: date_range)
                         .sum(:total_cost)

      agent_costs = Ai::AgentExecution
                      .joins(:agent)
                      .where(ai_agents: { account_id: account.id })
                      .where(created_at: date_range)
                      .sum(:cost_usd)

      # Get task counts
      workflow_runs = Ai::WorkflowRun
                        .joins(:workflow)
                        .where(ai_workflows: { account_id: account.id })
                        .where(created_at: date_range)

      successful_runs = workflow_runs.where(status: "completed").count
      avg_execution_hours = workflow_runs.where(status: "completed").average(:duration_ms)&.to_f&./(3_600_000) || 0
      manual_baseline = account.settings&.dig("ai_manual_baseline_hours")&.to_f || 0.25
      time_saved = [successful_runs * (manual_baseline - avg_execution_hours), 0].max

      # Update metric
      metric.assign_attributes(
        ai_cost_usd: (workflow_costs + agent_costs).to_f,
        total_cost_usd: (workflow_costs + agent_costs).to_f,
        time_saved_hours: time_saved,
        time_saved_value_usd: time_saved * DEFAULT_HOURLY_RATE,
        tasks_completed: workflow_runs.count,
        tasks_automated: successful_runs,
        errors_prevented: workflow_runs.where(status: "failed").count
      )

      metric.save!
      metric
    end

    # Class method: Get ROI trends for an account
    def self.roi_trends(account, days: 30)
      for_account(account)
        .daily
        .for_date_range(days.days.ago.to_date, Date.current)
        .order(period_date: :asc)
        .map do |m|
          {
            date: m.period_date,
            roi_percentage: m.roi_percentage,
            net_benefit: m.net_benefit_usd,
            total_cost: m.total_cost_usd,
            total_value: m.total_value_usd
          }
        end
    end

    # Class method: Aggregate ROI for a period
    def self.aggregate_for_period(account, period_type: "monthly", period_date: Date.current)
      date_range = date_range_for_period(period_type, period_date)

      daily_metrics = for_account(account)
                        .daily
                        .for_date_range(date_range.begin.to_date, date_range.end.to_date)

      return nil if daily_metrics.empty?

      {
        period_type: period_type,
        period_date: period_date,
        total_ai_cost: daily_metrics.sum(:ai_cost_usd),
        total_cost: daily_metrics.sum(:total_cost_usd),
        total_value: daily_metrics.sum(:total_value_usd),
        total_time_saved_hours: daily_metrics.sum(:time_saved_hours),
        total_tasks: daily_metrics.sum(:tasks_completed),
        total_automated: daily_metrics.sum(:tasks_automated),
        average_roi: daily_metrics.average(:roi_percentage)&.to_f&.round(2),
        total_net_benefit: daily_metrics.sum(:net_benefit_usd)
      }
    end

    private

    def calculate_derived_metrics
      # Calculate total cost
      self.total_cost_usd = (ai_cost_usd || 0) + (infrastructure_cost_usd || 0)

      # Calculate time saved value
      self.time_saved_value_usd ||= (time_saved_hours || 0) * DEFAULT_HOURLY_RATE

      # Calculate total value
      self.total_value_usd = (time_saved_value_usd || 0) +
                             (error_reduction_value_usd || 0) +
                             (throughput_value_usd || 0)

      # Calculate ROI
      self.roi_percentage = calculate_roi
      self.net_benefit_usd = calculate_net_benefit

      # Calculate per-task metrics
      if tasks_completed.present? && tasks_completed > 0
        self.cost_per_task_usd = total_cost_usd / tasks_completed
        self.value_per_task_usd = total_value_usd / tasks_completed
      end

      # Calculate efficiency gain
      if baseline_time_hours.present? && baseline_time_hours > 0 && time_saved_hours.present?
        self.efficiency_gain_percentage = (time_saved_hours / baseline_time_hours * 100).round(2)
      end
    end

    def recalculate_totals
      calculate_derived_metrics
    end

    def unique_period_metric
      existing = self.class.where(
        account_id: account_id,
        metric_type: metric_type,
        period_type: period_type,
        period_date: period_date,
        attributable_type: attributable_type,
        attributable_id: attributable_id
      ).where.not(id: id)

      if existing.exists?
        errors.add(:base, "ROI metric already exists for this period and resource")
      end
    end

    def self.date_range_for_period(period_type, period_date)
      case period_type
      when "daily"
        period_date.beginning_of_day..period_date.end_of_day
      when "weekly"
        period_date.beginning_of_week..period_date.end_of_week
      when "monthly"
        period_date.beginning_of_month..period_date.end_of_month
      when "quarterly"
        period_date.beginning_of_quarter..period_date.end_of_quarter
      when "yearly"
        period_date.beginning_of_year..period_date.end_of_year
      else
        period_date.beginning_of_day..period_date.end_of_day
      end
    end
  end
end
