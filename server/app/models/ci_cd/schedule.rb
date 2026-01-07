# frozen_string_literal: true

module CiCd
  # Scheduled pipeline execution configuration
  # Supports cron expressions for recurring pipeline runs
  class Schedule < ApplicationRecord
    include Schedulable

    self.table_name = "ci_cd_schedules"

    # ============================================
    # Associations
    # ============================================
    belongs_to :pipeline, class_name: "CiCd::Pipeline", foreign_key: :ci_cd_pipeline_id
    belongs_to :created_by, class_name: "User", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true
    # Note: cron_expression and timezone validations inherited from Schedulable

    # ============================================
    # Scopes
    # ============================================
    # Note: active_schedules and by_timezone inherited from Schedulable
    scope :active, -> { where(is_active: true) }
    scope :upcoming, -> { active_schedules.where("next_run_at > ?", Time.current).order(:next_run_at) }

    # ============================================
    # Instance Methods
    # ============================================

    def trigger!
      return unless is_active?

      pipeline.trigger_run!(
        trigger_type: "schedule",
        trigger_context: {
          schedule_id: id,
          schedule_name: name,
          scheduled_at: next_run_at&.iso8601
        }.merge(inputs)
      )

      update!(
        last_run_at: Time.current,
        next_run_at: next_execution_time
      )
    end

    def account
      pipeline.account
    end
  end
end
