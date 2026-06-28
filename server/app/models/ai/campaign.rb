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

    # How long a driver holds the single-driver lease before it must renew (drivers
    # renew on each unit of work). Sized so a crashed/abandoned driver's lease frees
    # itself without operator intervention, but long enough to span a normal iteration.
    DEFAULT_LEASE_TTL = 30.minutes

    belongs_to :account
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id", optional: true

    has_many :ralph_loops, class_name: "Ai::RalphLoop", foreign_key: "campaign_id", dependent: :nullify
    has_many :campaign_decisions, class_name: "Ai::CampaignDecision", foreign_key: "campaign_id", dependent: :destroy
    has_many :parked_questions, class_name: "Ai::ParkedQuestion", foreign_key: "campaign_id", dependent: :destroy
    has_many :progress_entries, class_name: "Ai::ProgressEntry", foreign_key: "campaign_id", dependent: :destroy
    has_many :campaign_lands, class_name: "Ai::CampaignLand", foreign_key: "campaign_id", dependent: :destroy
    # The proposal this campaign was spawned from (discovery/delegation control plane), if any.
    has_one :source_proposal, class_name: "Ai::CampaignProposal", foreign_key: "spawned_campaign_id",
                              inverse_of: :spawned_campaign, dependent: :nullify

    validates :name, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :decision_authority, presence: true, inclusion: { in: DECISION_AUTHORITY }

    scope :active, -> { where(status: "active") }
    scope :open, -> { where.not(status: TERMINAL_STATUSES) }
    scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }

    # ---- lifecycle ---------------------------------------------------------
    def start!
      update!(status: "active", started_at: started_at || Time.current, last_activity_at: Time.current)
    end

    # Heartbeat for the execution interface: bump when the campaign does real work
    # (decision, parked question, increment, lifecycle). Deliberately NOT called by
    # snapshot_progress!/status reads, so it reflects work, not monitoring polls.
    def touch_activity!
      update_column(:last_activity_at, Time.current) if has_attribute?(:last_activity_at)
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

    # ---- single-driver lease ----------------------------------------------
    # Advisory, expiring claim ensuring one driver works a campaign at a time. A
    # campaign/<id> branch + this progress ledger are mutated by whoever drives the
    # campaign; two concurrent drivers (e.g. two CC sessions, or a CC session + the
    # platform executor) race on git and the ledger. Drivers cooperatively claim the
    # lease before driving and renew it as they work; a second driver sees it held and
    # backs off. Atomic via row lock; expired leases are freely re-acquirable so a
    # crashed driver never wedges the campaign. Guarded with has_attribute? so the code
    # tolerates the columns being absent during the migration window (expand-contract).

    def driver_lease_active?
      return false unless has_attribute?(:driver_lease_holder)

      driver_lease_holder.present? && driver_lease_expires_at.present? && driver_lease_expires_at > Time.current
    end

    def driver_lease_info
      return nil unless driver_lease_active?

      { holder: driver_lease_holder, expires_at: driver_lease_expires_at }
    end

    # Acquire or renew the lease for `holder`. Returns true if `holder` now holds it,
    # false if a different driver holds an unexpired lease. The current holder renewing
    # always succeeds (extends the expiry). No-op allow before the columns exist.
    def acquire_driver_lease!(holder:, ttl: DEFAULT_LEASE_TTL)
      return true unless has_attribute?(:driver_lease_holder)
      raise ArgumentError, "lease holder is required" if holder.blank?

      acquired = false
      with_lock do
        if !driver_lease_active? || driver_lease_holder == holder
          update_columns(driver_lease_holder: holder, driver_lease_expires_at: Time.current + ttl)
          acquired = true
        end
      end
      acquired
    end

    # Release the lease iff `holder` holds it (or it's already free). Returns true when
    # the lease is free afterward, false when a different driver still holds it.
    def release_driver_lease!(holder:)
      return true unless has_attribute?(:driver_lease_holder)

      released = false
      with_lock do
        if driver_lease_holder.blank? || driver_lease_holder == holder
          update_columns(driver_lease_holder: nil, driver_lease_expires_at: nil)
          released = true
        end
      end
      released
    end

    # ---- decisions + parked questions -------------------------------------
    def record_decision!(decision_type:, title: nil, rationale: nil, task: nil, user: nil, metadata: {})
      decision = campaign_decisions.create!(
        decision_type: decision_type, title: title, rationale: rationale,
        ralph_task_id: task&.id, user_id: user&.id, metadata: metadata
      )
      touch_activity!
      decision
    end

    def park_question!(question:, context: nil, task: nil, metadata: {})
      pq = parked_questions.create!(question: question, context: context, ralph_task_id: task&.id, metadata: metadata)
      refresh_open_questions_count!
      touch_activity!
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

    # Unified, newest-first feed of campaign activity (decisions + parked questions
    # + completed tasks) so the execution interface / monitoring is one read instead
    # of polling git + the DB separately.
    def activity_feed(limit: 20)
      events = []
      campaign_decisions.order(created_at: :desc).limit(limit).each do |d|
        events << { kind: "decision", status: d.decision_type, title: d.title, at: d.created_at }
      end
      parked_questions.order(created_at: :desc).limit(limit).each do |q|
        events << { kind: "parked_question", status: q.status, title: q.question, at: q.created_at }
      end
      Ai::RalphTask.where(ralph_loop_id: ralph_loops.select(:id))
                   .where.not(iteration_completed_at: nil)
                   .order(iteration_completed_at: :desc).limit(limit).each do |t|
        events << { kind: "task", status: t.status, title: t.task_key, at: t.iteration_completed_at }
      end
      events.select { |e| e[:at] }.sort_by { |e| e[:at] }.reverse.first(limit)
    end

    def summary
      {
        id: id, name: name, status: status, decision_authority: decision_authority,
        loop_count: loop_count, total_tasks: total_tasks, completed_tasks: completed_tasks,
        failed_tasks: failed_tasks, blocked_tasks: blocked_tasks, open_questions: open_questions,
        completion_pct: completion_pct, started_at: started_at, completed_at: completed_at,
        # Guarded so the code tolerates the column being absent during the migration
        # window (expand-contract / running ahead of the schema).
        last_activity_at: (last_activity_at if has_attribute?(:last_activity_at)),
        driver_lease: (driver_lease_info if has_attribute?(:driver_lease_holder)),
        # Set by Ai::Land::RebaseAdvisor when the target branch advances past this
        # campaign's branch — surfaces "rebase needed" + likely conflicts on the dashboard.
        rebase_advisory: (configuration.is_a?(Hash) ? configuration["rebase_advisory"] : nil)
      }
    end
  end
end
