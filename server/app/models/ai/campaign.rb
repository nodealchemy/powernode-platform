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

    # Minimum number of terminal land attempts before the acceptance-rate floor
    # (stop_conditions["min_acceptance_pct"]) is allowed to stop a campaign — so a
    # young campaign whose first change happens to be rejected isn't killed on a
    # one-sample 0%. Override per campaign with stop_conditions["min_acceptance_sample"].
    DEFAULT_MIN_ACCEPTANCE_SAMPLE = 4

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

    # ---- land source seam (canonical land path) ---------------------------
    # Surface a land issue through this campaign's parked-questions queue so it
    # shows up on the dashboard for the operator. Invoked generically by
    # Ai::Land::LandService when the land's source is a campaign (the
    # equivalent mission hook is Ai::Mission#land_park_notify!).
    def land_park_notify!(reason:, land:)
      park_question!(
        question: "Campaign land needs attention: #{reason}",
        context: "land=#{land.id} #{land.source_branch} → #{land.target_branch}",
        metadata: { "campaign_land_id" => land.id, "reason" => reason }
      )
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

    # ---- acceptance / cost metrics (G2) ------------------------------------

    # Lands that reached a success terminal (the change was actually merged).
    def accepted_lands_count
      campaign_lands.where(status: "landed").count
    end

    # Lands that reached ANY terminal outcome (accepted or not) — the denominator
    # for acceptance rate. Excludes in-flight and "parked" (non-terminal/re-queueable).
    def terminal_lands_count
      campaign_lands.where(status: ::Ai::CampaignLand::TERMINAL_STATUSES).count
    end

    # Fraction of terminal land attempts that were accepted, as a percentage.
    # nil until at least one attempt has reached a terminal outcome (undefined,
    # not zero — so callers don't treat "no data yet" as a 0% net-loss).
    def acceptance_pct
      attempts = terminal_lands_count
      return nil if attempts.zero?

      (accepted_lands_count.to_f / attempts * 100).round(2)
    end

    # Total token/$ spend on the campaign's METERED (platform-executor) loops only —
    # flat-rate CLI-executor loops don't spend platform $, so they're excluded.
    def metered_spend
      ::Ai::RalphIteration.where(ralph_loop_id: ralph_loops.metered.select(:id)).sum(:cost)
    end

    # Cost per accepted change — metered loops only. nil when the campaign has no
    # metered loops (the metric doesn't apply to flat-rate work) or has yet to land
    # anything (avoid divide-by-zero / a meaningless infinity).
    def cost_per_accepted_change
      return nil unless ralph_loops.metered.exists?

      accepted = accepted_lands_count
      return nil if accepted.zero?

      (metered_spend / accepted).to_f.round(6)
    end

    # ---- stop policy -------------------------------------------------------
    def should_stop?
      return true if terminal?
      max_failed = stop_conditions["max_failed"]
      return true if max_failed && failed_tasks >= max_failed.to_i
      target = stop_conditions["completion_pct"]
      return true if target && completion_pct >= target.to_f
      return true if acceptance_floor_breached?
      false
    end

    # G2: net-loss / anti-churn guard — applies to BOTH runtimes. Once enough
    # changes have been attempted (a minimum sample), stop if the share that
    # actually landed has fallen below the configured floor. Inert until both a
    # floor is configured and the sample threshold is met.
    def acceptance_floor_breached?
      floor = stop_conditions["min_acceptance_pct"]
      return false if floor.blank?

      sample = (stop_conditions["min_acceptance_sample"] || DEFAULT_MIN_ACCEPTANCE_SAMPLE).to_i
      return false if terminal_lands_count < sample

      pct = acceptance_pct
      pct.present? && pct < floor.to_f
    end

    # Terminal finalization: complete the campaign when its work is genuinely
    # drained (all loops ended, every task terminal, no open questions) or a stop
    # condition is met — so a finished campaign doesn't linger at status=active /
    # completion_pct=100 forever. Idempotent. (Operator decision 2026-06-29.)
    def maybe_finalize!(summary = nil)
      return if terminal?
      return unless should_stop? || fully_drained?

      reason = should_stop? ? "stop condition met" : "work drained"
      complete!(summary || "Auto-finalized (#{reason}) at #{completion_pct}%")
    end

    # No further work pending: loops have ended (none active/scheduled), at least
    # one task ran, no question is open, and no task is non-terminal.
    def fully_drained?
      return false if ralph_loops.active.exists?
      return false unless ralph_loops.exists?
      return false if parked_questions.where(status: "open").exists?

      tasks = ::Ai::RalphTask.where(ralph_loop_id: ralph_loops.select(:id))
      tasks.exists? && tasks.where(status: %w[pending in_progress blocked]).none?
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
        # G2: anti-churn acceptance rate (both runtimes) + cost-per-accepted (metered only).
        acceptance_pct: acceptance_pct, cost_per_accepted_change: cost_per_accepted_change,
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
