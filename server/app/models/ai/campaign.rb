# frozen_string_literal: true

module Ai
  # An Autonomous Improvement Campaign — a first-class, durable wrapper around the dev-improve
  # Ralph loop. It owns its configuration (scope/posture/ordering/decision-authority/stop), a
  # decision log, an async parked-questions queue, a progress ledger, and the Ralph loops it
  # drives. Replaces the previously hand-authored standing prompt + markdown plan files so a run
  # is start(config) and is reliably repeatable.
  class Campaign < ApplicationRecord
    include Auditable

    STATUSES = %w[created active paused completed archived].freeze
    TERMINAL_STATUSES = %w[completed archived].freeze
    # How much the driver may decide on its own before parking a question for the operator:
    #   supervised — ask before any fork; monitored — decide low-risk, ask on medium;
    #   trusted    — decide design/architecture forks per best practice, park only
    #                live-credential / irreversible-external / business-policy-value items;
    #   autonomous — trusted + auto-refill the backlog and keep going until empty/halted.
    DECISION_AUTHORITY = %w[supervised monitored trusted autonomous].freeze

    belongs_to :account
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id", optional: true

    has_many :ralph_loops, class_name: "Ai::RalphLoop", foreign_key: "campaign_id", dependent: :nullify
    has_many :campaign_decisions, class_name: "Ai::CampaignDecision", foreign_key: "campaign_id", dependent: :destroy
    has_many :parked_questions, class_name: "Ai::ParkedQuestion", foreign_key: "campaign_id", dependent: :destroy
    has_many :progress_entries, class_name: "Ai::ProgressEntry", foreign_key: "campaign_id", dependent: :destroy

    validates :name, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :decision_authority, presence: true, inclusion: { in: DECISION_AUTHORITY }

    scope :active, -> { where(status: "active") }
    scope :open, -> { where.not(status: TERMINAL_STATUSES) }
    scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }

    # ---- lifecycle ---------------------------------------------------------
    def start!
      update!(status: "active", started_at: started_at || Time.current)
    end

    def pause!(reason = nil)
      update!(status: "paused", paused_at: Time.current, paused_reason: reason)
    end

    def resume!
      update!(status: "active", paused_at: nil, paused_reason: nil)
    end

    def complete!(summary = nil)
      update!(status: "completed", completed_at: Time.current, completion_summary: summary)
    end

    def archive!
      update!(status: "archived")
    end

    def terminal?
      status.in?(TERMINAL_STATUSES)
    end

    # ---- decisions + parked questions -------------------------------------
    def record_decision!(decision_type:, title: nil, rationale: nil, task: nil, user: nil, metadata: {})
      campaign_decisions.create!(
        decision_type: decision_type, title: title, rationale: rationale,
        ralph_task_id: task&.id, user_id: user&.id, metadata: metadata
      )
    end

    def park_question!(question:, context: nil, task: nil, metadata: {})
      pq = parked_questions.create!(question: question, context: context, ralph_task_id: task&.id, metadata: metadata)
      refresh_open_questions_count!
      pq
    end

    def open_questions_list
      parked_questions.where(status: "open").order(created_at: :asc)
    end

    def refresh_open_questions_count!
      update_column(:open_questions, parked_questions.where(status: "open").count)
    end

    # ---- progress ----------------------------------------------------------
    # Roll up the driven loops' task counts, persist a ledger snapshot, and update the
    # denormalized aggregates used by the dashboard.
    def snapshot_progress!
      loops = ralph_loops.to_a
      totals = { total: 0, completed: 0, failed: 0, blocked: 0 }
      per_loop = {}
      loops.each do |loop|
        tasks = loop.ralph_tasks
        c = { total: tasks.count, completed: tasks.where(status: "passed").count,
              failed: tasks.where(status: "failed").count, blocked: tasks.where(status: "blocked").count }
        totals.each_key { |k| totals[k] += c[k] }
        per_loop[loop.id] = c.merge(name: loop.name)
      end
      pct = totals[:total].positive? ? (totals[:completed].to_f / totals[:total] * 100).round(2) : 0.0

      entry = progress_entries.create!(
        recorded_at: Time.current,
        total_tasks: totals[:total], completed_tasks: totals[:completed],
        failed_tasks: totals[:failed], blocked_tasks: totals[:blocked],
        completion_pct: pct, per_loop_summary: per_loop
      )
      update!(
        loop_count: loops.size, total_tasks: totals[:total], completed_tasks: totals[:completed],
        failed_tasks: totals[:failed], blocked_tasks: totals[:blocked],
        open_questions: parked_questions.where(status: "open").count
      )
      entry
    end

    def completion_pct
      total_tasks.positive? ? (completed_tasks.to_f / total_tasks * 100).round(2) : 0.0
    end

    # ---- stop policy -------------------------------------------------------
    def should_stop?
      return true if terminal?
      max_failed = stop_conditions["max_failed"]
      return true if max_failed && failed_tasks >= max_failed.to_i
      target = stop_conditions["completion_pct"]
      return true if target && completion_pct >= target.to_f
      false
    end

    def summary
      {
        id: id, name: name, status: status, decision_authority: decision_authority,
        loop_count: loop_count, total_tasks: total_tasks, completed_tasks: completed_tasks,
        failed_tasks: failed_tasks, blocked_tasks: blocked_tasks, open_questions: open_questions,
        completion_pct: completion_pct, started_at: started_at, completed_at: completed_at
      }
    end
  end
end
