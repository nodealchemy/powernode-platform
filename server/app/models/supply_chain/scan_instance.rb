# frozen_string_literal: true

module SupplyChain
  class ScanInstance < ApplicationRecord
    include Auditable
    include Schedulable

    self.table_name = "supply_chain_scan_instances"

    # ============================================
    # Constants
    # ============================================
    STATUSES = %w[active paused disabled].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :scan_template, class_name: "SupplyChain::ScanTemplate"
    belongs_to :installed_by, class_name: "User", optional: true

    has_many :executions, class_name: "SupplyChain::ScanExecution",
             foreign_key: :scan_instance_id, dependent: :destroy

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :scan_template_id, uniqueness: { scope: :account_id, message: "already installed for this account" }
    validates :execution_count, numericality: { greater_than_or_equal_to: 0 }
    validates :success_count, numericality: { greater_than_or_equal_to: 0 }
    validates :failure_count, numericality: { greater_than_or_equal_to: 0 }

    # ============================================
    # Scopes
    # ============================================
    scope :by_status, ->(status) { where(status: status) }
    scope :active, -> { where(status: "active") }
    scope :paused, -> { where(status: "paused") }
    scope :disabled, -> { where(status: "disabled") }
    scope :scheduled, -> { where.not(schedule_cron: nil) }
    scope :due_for_execution, -> { active.scheduled.where("next_execution_at IS NULL OR next_execution_at <= ?", Time.current) }
    scope :by_template, ->(template_id) { where(scan_template_id: template_id) }
    scope :recent, -> { order(created_at: :desc) }

    # ============================================
    # Callbacks
    # ============================================
    before_save :sanitize_jsonb_fields
    before_save :calculate_next_execution, if: :schedule_cron_changed?

    # ============================================
    # Instance Methods
    # ============================================
    def active?
      status == "active"
    end

    def paused?
      status == "paused"
    end

    def disabled?
      status == "disabled"
    end

    def scheduled?
      schedule_cron.present?
    end

    def due_for_execution?
      active? && scheduled? && (next_execution_at.nil? || next_execution_at <= Time.current)
    end

    def success_rate
      return 0 if execution_count == 0

      ((success_count.to_f / execution_count) * 100).round(2)
    end

    def activate!
      update!(status: "active")
    end

    def pause!
      update!(status: "paused")
    end

    def disable!
      update!(status: "disabled")
    end

    def execute!(triggered_by: nil, input: {})
      return nil unless active?

      execution = executions.create!(
        account: account,
        triggered_by: triggered_by,
        trigger_type: triggered_by.present? ? "manual" : "scheduled",
        input_data: input,
        status: "pending"
      )

      # Enqueue the execution job
      # SupplyChain::ScanExecutionJob.perform_later(execution.id)

      execution
    end

    def record_execution_result!(success:)
      if success
        increment!(:success_count)
      else
        increment!(:failure_count)
      end
      increment!(:execution_count)

      update!(
        last_execution_at: Time.current,
        next_execution_at: calculate_next_execution_time
      )
    end

    def latest_execution
      executions.order(created_at: :desc).first
    end

    def recent_executions(limit = 10)
      executions.order(created_at: :desc).limit(limit)
    end

    def update_configuration!(new_config)
      validation = scan_template.validate_configuration(new_config)

      if validation[:valid]
        update!(configuration: new_config)
        true
      else
        errors.add(:configuration, validation[:errors].join(", "))
        false
      end
    end

    def template_name
      scan_template.name
    end

    def template_category
      scan_template.category
    end

    def summary
      {
        id: id,
        name: name,
        description: description,
        scan_template_id: scan_template_id,
        template_name: template_name,
        template_category: template_category,
        status: status,
        schedule_cron: schedule_cron,
        execution_count: execution_count,
        success_count: success_count,
        failure_count: failure_count,
        success_rate: success_rate,
        last_execution_at: last_execution_at,
        next_execution_at: next_execution_at,
        created_at: created_at
      }
    end

    def detailed_instance
      {
        summary: summary,
        configuration: configuration,
        template: scan_template.summary,
        recent_executions: recent_executions.map(&:summary)
      }
    end

    private

    def sanitize_jsonb_fields
      self.configuration ||= {}
      self.metadata ||= {}
    end

    def calculate_next_execution
      self.next_execution_at = calculate_next_execution_time
    end

    def calculate_next_execution_time
      return nil unless schedule_cron.present?

      # Use a cron parser to calculate next run time
      # This is a placeholder - would use a gem like 'fugit' or 'parse-cron'
      1.hour.from_now
    end
  end
end
