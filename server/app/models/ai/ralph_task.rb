# frozen_string_literal: true

module Ai
  class RalphTask < ApplicationRecord
    # ==================== Concerns ====================
    include Auditable

    audit_account_via :ralph_loop

    # ==================== Constants ====================
    STATUSES = %w[pending in_progress passed failed blocked skipped].freeze
    TERMINAL_STATUSES = %w[passed failed skipped].freeze

    # Execution type enumeration - determines which type of executor handles this task
    EXECUTION_TYPES = %w[agent pipeline a2a_task container human community].freeze

    # Capability match strategies for executor selection
    CAPABILITY_STRATEGIES = %w[all any weighted].freeze

    # Tier-2(c): improvement-metric tuning
    DURABILITY_WINDOW = 7.days     # a pass must survive this long to count as durable
    BLAST_RADIUS_CAP = 10          # cap a single task's blast-radius weight
    KIND_VELOCITY_CAP = 20         # cap one kind's positive velocity contribution
    REVERT_THROTTLE_RATE = 0.3     # kinds reverting >= this fraction are flagged throttled

    # A claim past this age with no progress signal is surfaced as `stale` to
    # orchestrating sessions (dev_list_tasks / dev_next_task) so a stalled
    # background driver isn't invisible until an operator stumbles on it.
    STALE_CLAIM_THRESHOLD = (ENV["RALPH_TASK_STALE_CLAIM_MINUTES"].presence || "20").to_i.minutes

    # ==================== Associations ====================
    belongs_to :ralph_loop, class_name: "Ai::RalphLoop", foreign_key: "ralph_loop_id"

    has_many :ralph_iterations, class_name: "Ai::RalphIteration",
             foreign_key: "ralph_task_id", dependent: :nullify

    # Polymorphic executor association - links to the actual executor instance
    belongs_to :executor, polymorphic: true, optional: true

    # Tracks the last executor used (for retry/fallback scenarios)
    belongs_to :last_executor, polymorphic: true, optional: true

    # ==================== Validations ====================
    validates :task_key, presence: true
    validates :task_key, uniqueness: { scope: :ralph_loop_id }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :priority, numericality: { only_integer: true }, allow_nil: true
    validates :execution_type, inclusion: { in: EXECUTION_TYPES }
    validates :capability_match_strategy, inclusion: { in: CAPABILITY_STRATEGIES }

    # ==================== Scopes ====================
    scope :pending, -> { where(status: "pending") }
    scope :in_progress, -> { where(status: "in_progress") }
    scope :passed, -> { where(status: "passed") }
    scope :failed, -> { where(status: "failed") }
    scope :blocked, -> { where(status: "blocked") }
    scope :skipped, -> { where(status: "skipped") }
    scope :terminal, -> { where(status: TERMINAL_STATUSES) }
    scope :active, -> { where(status: %w[pending in_progress blocked]) }
    scope :by_priority, -> { order(priority: :desc, position: :asc) }
    scope :ordered, -> { order(position: :asc, priority: :desc) }
    # Tier-2(c): revert tracking for the ungameable improvement metric
    scope :reverted, -> { where.not(reverted_at: nil) }
    scope :not_reverted, -> { where(reverted_at: nil) }
    # A durable improvement = passed, never reverted, matured past the window.
    scope :durable, ->(window = DURABILITY_WINDOW) { passed.not_reverted.where("iteration_completed_at <= ?", window.ago) }

    # ==================== Callbacks ====================
    before_validation :set_position, on: :create
    after_commit :update_loop_task_counts
    after_save :broadcast_task_status_change, if: :saved_change_to_status?

    # ==================== State Machine Methods ====================

    def start!
      raise InvalidTransitionError, "Cannot start task in #{status} status" unless can_start?

      update!(status: "in_progress")
    end

    def pass!(iteration_number: nil)
      raise InvalidTransitionError, "Cannot pass task in #{status} status" unless can_pass?

      update!(
        status: "passed",
        iteration_completed_at: Time.current,
        completed_in_iteration: iteration_number,
        error_message: nil,
        error_code: nil
      )

      unblock_dependent_tasks
    end

    def fail!(error_message: nil, error_code: nil)
      raise InvalidTransitionError, "Cannot fail task in #{status} status" unless can_fail?

      update!(
        status: "failed",
        iteration_completed_at: Time.current,
        error_message: error_message,
        error_code: error_code
      )
    end

    # blocked_for distinguishes WHY the task is blocked, so downstream code (see
    # #review_parked?) can tell an operator-review park apart from a routine
    # unmet-dependency block. nil preserves the old behaviour for callers that
    # don't care (legacy rows are still classified via #review_parked?'s
    # message-marker fallback).
    def block!(reason: nil, blocked_for: nil)
      raise InvalidTransitionError, "Cannot block task in #{status} status" unless can_block?

      update!(status: "blocked", error_message: reason)
      # Targeted merge, not a whole-column rewrite: this runs under the task-row
      # lock while the claim path writes the same column under the LOOP lock.
      merge_metadata!("blocked_for" => blocked_for) if blocked_for.present?
    end

    def skip!(reason: nil)
      raise InvalidTransitionError, "Cannot skip task in #{status} status" unless can_skip?

      update!(
        status: "skipped",
        iteration_completed_at: Time.current,
        error_message: reason
      )

      unblock_dependent_tasks
    end

    def resume!
      raise InvalidTransitionError, "Cannot resume task in #{status} status" unless can_resume?

      record_execution_attempt!
    end

    def reset!
      update!(
        status: "pending",
        iteration_completed_at: nil,
        completed_in_iteration: nil,
        error_message: nil,
        error_code: nil
      )
    end

    # ==================== Revert Tracking (Tier-2c) ====================

    # Mark a previously-committed task as reverted. Orthogonal to the pass/fail
    # state machine: the task keeps its terminal status but stops counting as a
    # durable improvement and raises its kind's revert_rate. Ground-truth signal
    # behind net_improvement_velocity — explicit (operator- or rollback-driven),
    # never inferred from self-reported checks.
    def revert!(reason: nil)
      update!(reverted_at: Time.current, revert_reason: reason)
    end

    def unrevert!
      update!(reverted_at: nil, revert_reason: nil)
    end

    def reverted?
      reverted_at.present?
    end

    # A durable improvement: passed, never reverted, and old enough to have
    # survived the observation window (default 7 days).
    def durable?(window: DURABILITY_WINDOW)
      status == "passed" && !reverted? && iteration_completed_at.present? && iteration_completed_at <= window.ago
    end

    # Blast-radius weight for the improvement metric: how many files the change
    # touched (seeded at promotion from the recommendation's evidence), floored at
    # 1 and capped so one sprawling change can't dominate the velocity score.
    def blast_radius
      raw = metadata.is_a?(Hash) ? metadata["blast_radius"].to_i : 0
      raw.clamp(1, BLAST_RADIUS_CAP)
    end

    # ==================== Improvement Metric (Tier-2c) ====================

    # Ungameable improvement scoreboard for an account, computed from ground truth
    # (reverted_at / status / metadata.kind) — never from self-reported checks.
    # Revert-adjusted, per-kind revert_rate + throttle flag, blast-radius weighted,
    # and per-kind capped so spamming one easy kind can't inflate it. Reused by
    # get_ralph_loop_statistics and /improve status (one source of truth).
    def self.improvement_scoreboard(account:, window_days: 30)
      since = window_days.days.ago
      tasks = joins(:ralph_loop)
              .where(ai_ralph_loops: { account_id: account.id })
              .where("ai_ralph_tasks.metadata->>'kind' IS NOT NULL")
              .where("ai_ralph_tasks.updated_at >= ?", since)
              .to_a

      per_kind = {}
      net = 0.0

      tasks.group_by { |t| t.metadata["kind"] }.each do |kind, group|
        completed = group.count { |t| t.status == "passed" }
        reverted  = group.count(&:reverted?)
        durable   = group.select(&:durable?)
        revert_rate = completed.positive? ? (reverted.to_f / completed).round(3) : 0.0

        per_kind[kind] = {
          completed: completed,
          reverted: reverted,
          durable: durable.size,
          revert_rate: revert_rate,
          throttled: revert_rate >= REVERT_THROTTLE_RATE
        }

        weighted = durable.sum(&:blast_radius)
        net += [weighted, KIND_VELOCITY_CAP].min - reverted
      end

      weeks = [window_days / 7.0, 1.0].max
      {
        window_days: window_days,
        net_improvement_velocity: (net / weeks).round(2),
        total_durable: per_kind.values.sum { |k| k[:durable] },
        total_reverted: per_kind.values.sum { |k| k[:reverted] },
        per_kind: per_kind
      }
    end

    # ==================== State Checks ====================

    def can_start?
      status == "pending" && dependencies_satisfied?
    end

    def can_resume?
      status == "in_progress"
    end

    # in_progress: normal completion of claimed work.
    # blocked: operator resolution of a task that stopped for a decision.
    def can_pass?
      status.in?(%w[in_progress blocked])
    end

    def can_fail?
      status.in?(%w[in_progress blocked])
    end

    def can_block?
      status.in?(%w[pending in_progress])
    end

    def can_skip?
      status.in?(%w[pending blocked])
    end

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def repeating?
      repeating == true
    end

    def in_progress?
      status == "in_progress"
    end

    # ==================== Staleness (read-only signal) ====================

    # Timestamp the task was claimed via dev_next_task, or nil if never claimed
    # (or the claim predates this stamp being written).
    def claimed_at
      ts = metadata.is_a?(Hash) ? metadata["claimed_at"] : nil
      return nil if ts.blank?

      Time.zone.parse(ts.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def claimed_duration_seconds
      return nil unless in_progress? && claimed_at

      (Time.current - claimed_at).round
    end

    # A task has no mid-task progress signal today (iterations are only
    # recorded on dev_complete_task), so "no progress since claim" reduces to
    # "still in_progress past the staleness threshold" — a claim that has sat
    # untouched long enough to warrant a look, not a guarantee it's stuck.
    def stale?
      return false unless in_progress?

      ts = claimed_at
      return false unless ts

      ts <= STALE_CLAIM_THRESHOLD.ago
    end

    # ==================== Dependency Management ====================

    def dependencies_satisfied?
      return true if dependencies.blank?

      dependency_tasks = ralph_loop.ralph_tasks.where(task_key: dependencies)
      dependency_tasks.all? { |t| t.status.in?(%w[passed skipped]) }
    end

    def blocking_dependencies
      return [] if dependencies.blank?

      ralph_loop.ralph_tasks
                .where(task_key: dependencies)
                .where.not(status: %w[passed skipped])
                .pluck(:task_key)
    end

    def dependent_tasks
      ralph_loop.ralph_tasks.select do |task|
        task.dependencies&.include?(task_key)
      end
    end

    def unblock_dependent_tasks
      dependent_tasks.each do |task|
        next unless task.status == "blocked" && !task.review_parked? && task.dependencies_satisfied?

        task.update!(status: "pending")
      end
    end

    # "blocked" is overloaded: it means either (a) waiting on an unmet
    # dependency — safe to auto-unblock once the dependency clears — or (b)
    # parked for OPERATOR review (scope-guardrail violation, human execution
    # type) — must never be silently auto-unblocked, since dependencies being
    # satisfied is orthogonal to why it was parked.
    #
    # Prefers the explicit metadata["blocked_for"] stamp (set by block! going
    # forward); falls back to the pre-existing error_message markers for rows
    # blocked before that stamp existed.
    def review_parked?
      return false unless status == "blocked"

      blocked_for = metadata.is_a?(Hash) ? metadata["blocked_for"] : nil
      return blocked_for == "review" if blocked_for.present?

      msg = error_message.to_s
      msg.include?("[scope-guardrail]") || msg.include?("Awaiting human review")
    end

    # ==================== Executor Selection ====================

    # Find matching executor based on execution_type and required_capabilities
    def find_matching_executor
      case execution_type
      when "agent"
        find_matching_agent
      when "a2a_task"
        find_via_a2a_discovery
      when "community"
        find_community_agent
      when "pipeline"
        find_matching_pipeline
      when "container"
        find_matching_container
      when "human"
        find_human_reviewer
      else
        executor # Use pre-assigned executor
      end
    end

    # Increment execution attempts when starting execution
    def record_execution_attempt!(new_executor = nil)
      attrs = { execution_attempts: execution_attempts + 1 }
      if new_executor
        attrs[:last_executor_type] = new_executor.class.name
        attrs[:last_executor_id] = new_executor.id
      end
      update!(attrs)
    end

    # Check if fallback executor is configured
    def has_fallback?
      delegation_config["fallback_executor_type"].present?
    end

    # Get fallback executor configuration
    def fallback_config
      {
        executor_type: delegation_config["fallback_executor_type"],
        executor_id: delegation_config["fallback_executor_id"]
      }
    end

    # Check if delegation to specific agent is allowed
    def delegation_allowed_for?(agent_id)
      allowed = delegation_config["allowed_agents"]
      return true if allowed.blank? # No restrictions
      allowed.include?(agent_id.to_s)
    end

    # Get timeout for task execution
    def execution_timeout
      delegation_config["timeout_seconds"] || 3600
    end

    # ==================== Operator Amendment ====================

    # A promoted task's brief was write-once until now: ImprovementPromotionService
    # composed `acceptance_criteria` at approval time and nothing could amend it,
    # so a decision the operator made AFTER approving (scope narrowed, one of two
    # offered directions chosen) had no way onto the record the executor actually
    # reads. Both this and #apply_operator_edit! ride to the executor inside
    # #task_details, which dev_next_task returns verbatim.
    #
    # `status` is deliberately absent: it is owned by the AASM transitions behind
    # dev_complete_task, and hand-editing it would desynchronise the queue counts
    # and the iteration record. Same reasoning for position/execution_attempts/
    # reverted_at — loop bookkeeping, not operator intent.
    # `executor_type` is absent on purpose. It is the polymorphic type half of the
    # executor association and has NO inclusion validation, so an arbitrary string
    # persists happily and then raises NameError the moment anything calls
    # #executor — including Ai::Ralph::TaskExecutor#resolve_executor, which runs in
    # a request path. The REST task_params does not permit it either.
    #
    # `executor_id` goes with it. Without executor_type the polymorphic
    # association never resolves, so promoted tasks (which never set the type)
    # would accept a "pin" that #executor ignores entirely — resolve_executor
    # falls through to the loop default agent while dev_update_task reports
    # success. An editable field that cannot affect behaviour is worse than none.
    OPERATOR_EDITABLE_FIELDS = %w[
      description acceptance_criteria priority execution_type
      capability_match_strategy required_capabilities delegation_config
    ].freeze

    # The two jsonb editables need a shape check for the same reason executor_type
    # is excluded: nothing validates them, so a scalar persists and only raises
    # much later, away from the seam that accepted it. `delegation_config: 3600`
    # made #execution_timeout and #has_fallback? raise TypeError on the delegation
    # path; `required_capabilities: "ruby"` breaks the (required_capabilities -
    # slugs) subtraction in A2A discovery. The REST task_params constrains both
    # via strong params; the MCP seam had no equivalent.
    OPERATOR_FIELD_SHAPES = { "delegation_config" => Hash, "required_capabilities" => Array }.freeze

    # Cap on the append-only operator journal. metadata rides EVERY dev_next_task
    # claim payload (task_details is returned verbatim), and each entry stores the
    # full prior value — so uncapped, N brief amendments put N copies of the brief
    # in front of the executor on every claim. Same reasoning as DevLoopTool's
    # BASE_CONTEXT_*_LIMIT budgets on that payload.
    # Fields that define what "done" means. An amendment can only lower the bar
    # the executor is judged against through one of these.
    BRIEF_FIELDS = %w[description acceptance_criteria].freeze

    OPERATOR_JOURNAL_LIMIT = 10
    OPERATOR_JOURNAL_VALUE_LIMIT = 2_048

    # Applies an operator amendment and returns the list of fields that actually
    # changed. Raises ActiveRecord::RecordInvalid on a bad value rather than
    # persisting it — the caller surfaces the validation message.
    #
    # Every overwrite is journalled into metadata["operator_edits"] with its prior
    # value. The offer text carries the discovery `verifier_evidence`, and that
    # provenance is what makes the improvement queue auditable; an edit may replace
    # it, but must not make the original unrecoverable.
    # An amendment only reaches an executor through a FUTURE dev_next_task payload,
    # so name the cases where that will not happen. Shared by every amendment seam
    # (dev_update_task and approve_improvement's direction) — an operator who gets
    # `success: true` must not be left assuming delivery.
    def amendment_delivery_warning
      if in_progress?
        "task #{task_key} is in_progress — its executor already holds the previous brief; " \
          "the amendment lands only if the task is re-queued or re-claimed."
      elsif terminal?
        "task #{task_key} is #{status} (terminal) — the amendment is recorded but will " \
          "not be delivered unless the task is re-queued."
      elsif status == "blocked"
        # Not in TERMINAL_STATUSES, but dev_next_task claims only `pending`, so a
        # blocked task is undeliverable too — and it is the state most likely to
        # BE amended (a scope-guardrail park, or an operator answering the
        # question that blocked it).
        "task #{task_key} is blocked — dev_next_task claims only pending tasks, so the " \
          "amendment is recorded but will not be delivered until the task is re-queued " \
          "(dev_complete_task disposition or re-approval)."
      elsif execution_type == "human"
        "task #{task_key} has execution_type \"human\" — dev_next_task skips human tasks, so it " \
          "stays pending in dev_list_tasks but will never be handed to a drain session."
      end
    end

    # `meta` adds caller-owned metadata keys (e.g. operator_direction) written
    # inside the same lock. Callers must NOT pre-assign task.metadata themselves:
    # with_lock refuses a record with unpersisted changes, and a hash built before
    # the reload is stale by definition.
    # Targeted jsonb merge for the metadata column — the ONLY sanctioned way to
    # write it.
    #
    # metadata has several independent writers (the claim stamps, block!'s
    # blocked_for, delegation bookkeeping, injected_learning_ids, operator edits)
    # and they do NOT share a lock: the claim path holds the loop row while
    # dev_complete_task holds the task row. Any whole-column rewrite therefore
    # drops whatever another writer committed in between — losing blocked_for
    # breaks #blocked_reason, losing the claim stamps breaks re-claim and #stale?.
    # `||` replaces only the keys in `patch`, which makes the differing locks
    # harmless instead of requiring one shared mutex across all of them.
    #
    # updated_at is bumped explicitly because update_all skips callbacks AND
    # timestamps — without it a metadata-only write left task_details showing a
    # stale updated_at and fell outside improvement_scoreboard's window.
    def merge_metadata!(patch)
      patch = patch.to_h.stringify_keys
      return self if patch.empty?

      self.class.where(id: id).update_all([
        "metadata = COALESCE(metadata, '{}'::jsonb) || ?::jsonb, updated_at = ?",
        patch.to_json, Time.current
      ])
      reload
    end

    def apply_operator_edit!(attrs, note: nil, author: nil, meta: {}, edit_source: nil)
      # compact: an MCP/LLM caller routinely sends `null` for a declared-but-unset
      # optional param. Without this, nil != current value reads as an intentional
      # change and blanks the field — `acceptance_criteria: null` would silently
      # erase the entire executor brief. There is no "clear this field" use case.
      attrs = attrs.to_h.stringify_keys.slice(*OPERATOR_EDITABLE_FIELDS).compact
      OPERATOR_FIELD_SHAPES.each do |field, shape|
        next unless attrs.key?(field)
        next if attrs[field].is_a?(shape)

        raise ArgumentError, "#{field} must be #{shape == Hash ? 'an object' : 'an array'}, " \
                             "got #{attrs[field].class.name}"
      end
      # operator_direction is EXEMPT from truncation: ImprovementPromotionService
      # #strip_direction removes the prior header by exact string match against
      # this stored value, so a truncated copy matches nothing and the next
      # revision stacks a second contradictory "do not re-litigate" order — the
      # very failure the direction feature exists to prevent.
      extra_meta = meta.to_h.stringify_keys.map do |k, v|
        [k, (v.is_a?(String) && k != "operator_direction") ? v.truncate(OPERATOR_JOURNAL_VALUE_LIMIT) : v]
      end.to_h
      stamp = Time.current.iso8601
      changed = []

      # The reload below silently DISCARDS unpersisted changes, where the previous
      # task-row with_lock raised on them. Keep the loud contract: a caller that
      # pre-assigns (rather than passing attrs/meta) must fail, not lose its write.
      if changed?
        raise ArgumentError, "apply_operator_edit! requires a clean record; " \
                             "pass changes via attrs/meta instead of assigning first " \
                             "(dirty: #{changes.keys.join(', ')})"
      end

      # LOCK THE TASK ROW, and touch ONLY our own metadata keys.
      #
      # Lock choice is a deadlock question, not just a serialization one.
      # dev_complete_task takes task.with_lock and then reaches the LOOP row
      # (record_outcome -> iteration.complete! -> RalphLoop#add_learning), i.e.
      # task->loop. An earlier version of this method took loop->task, which is a
      # textbook AB/BA inversion: an operator amending while an executor reports
      # deadlocks, and Postgres aborts one side with ActiveRecord::Deadlocked,
      # unrescued at either seam. Same order as complete_task = no cycle.
      #
      # That alone would not serialize against the CLAIM path, which writes
      # claimed_by/claimed_holder/claimed_at under the LOOP lock. So instead of
      # rewriting the whole jsonb column, the metadata write is a SQL-level merge
      # of just the keys we own — a concurrent claim's keys survive because we
      # never write them back. Serializing everything on one mutex would need all
      # three writers changed at once; tracked as 019fedd5-c1a4.
      with_lock do
        reload
        current = metadata.presence || {}
        patch = extra_meta.dup
        changed << "metadata" if extra_meta.any? && current.merge(extra_meta) != current

        # A callable value is evaluated HERE, inside the lock, against
        # post-reload state, and receives the field's current value. Callers
        # deriving a new value from the existing one (e.g. prefixing a direction
        # onto the current brief) MUST use this form: computing it before the
        # call reads pre-lock state and silently overwrites whatever committed in
        # between.
        attrs = attrs.to_h do |field, value|
          [field, value.respond_to?(:call) ? value.call(public_send(field)) : value]
        end

        attrs.each do |field, value|
          previous = public_send(field)
          next if previous.to_s == value.to_s

          changed << field
          # Recorded OUTSIDE the capped journal. The credit guard keys on THIS,
          # not on operator_edits: that array is truncated to
          # OPERATOR_JOURNAL_LIMIT on every write and EVERY editable field
          # journals an entry, so a handful of trivial edits (priority flips)
          # evicted the brief edit and bought the credit back. Bounded by the
          # number of distinct authors, not by edit count. An operator's
          # approval-time direction is deliberately excluded — that is the
          # operator's own decision, not an executor amending its own brief.
          if BRIEF_FIELDS.include?(field) && author.present? && edit_source != "approval_direction"
            patch["brief_amended_by"] =
              (Array(patch["brief_amended_by"].presence || current["brief_amended_by"]) + [ author ]).uniq
          end
          patch["operator_edits"] = (Array(patch["operator_edits"].presence || current["operator_edits"]) +
                                     [{ "field" => field, "author" => author, "at" => stamp,
                                        "source" => edit_source,
                                        "previous" => previous.to_s.truncate(OPERATOR_JOURNAL_VALUE_LIMIT) }.compact])
                                    .last(OPERATOR_JOURNAL_LIMIT)
        end

        if note.present?
          changed << "note"
          patch["operator_notes"] = (Array(current["operator_notes"]) +
                                     [{ "author" => author, "at" => stamp,
                                        "note" => note.to_s.truncate(OPERATOR_JOURNAL_VALUE_LIMIT) }])
                                    .last(OPERATOR_JOURNAL_LIMIT)
        end

        next if changed.empty?

        update!(attrs) if attrs.any?
        # `||` merges at the top level, so only the keys in `patch` are replaced.
        merge_metadata!(patch)
      end

      changed
    end

    # ==================== Summary Methods ====================

    def task_summary
      {
        id: id,
        task_key: task_key,
        description: description&.truncate(200),
        status: status,
        priority: priority,
        position: position,
        dependencies: dependencies,
        dependencies_satisfied: dependencies_satisfied?,
        completed_in_iteration: completed_in_iteration,
        iteration_completed_at: iteration_completed_at&.iso8601,
        execution_type: execution_type,
        executor_type: executor_type,
        executor_id: executor_id,
        execution_attempts: execution_attempts,
        reverted: reverted?,
        stale: stale?,
        claimed_duration_seconds: claimed_duration_seconds
      }
    end

    def task_details
      task_summary.merge(
        description: description,
        acceptance_criteria: acceptance_criteria,
        error_message: error_message,
        error_code: error_code,
        metadata: metadata,
        blocking_dependencies: blocking_dependencies,
        iterations_count: ralph_iterations.count,
        required_capabilities: required_capabilities,
        capability_match_strategy: capability_match_strategy,
        delegation_config: delegation_config,
        created_at: created_at.iso8601,
        updated_at: updated_at.iso8601
      )
    end

    # ==================== Custom Errors ====================

    class InvalidTransitionError < StandardError; end

    private

    def set_position
      return if position.present?

      max_position = ralph_loop.ralph_tasks.maximum(:position) || 0
      self.position = max_position + 1
    end

    def broadcast_task_status_change
      mission = ralph_loop&.mission || ::Ai::Mission.find_by(ralph_loop_id: ralph_loop_id)
      return unless mission

      MissionChannel.broadcast_mission_event(mission.id, "task_status_changed", {
        task_id: id,
        task_key: task_key,
        status: status,
        previous_status: saved_change_to_status.first,
        execution_type: execution_type,
        phase: metadata&.dig("phase")
      })
    rescue StandardError => e
      Rails.logger.warn("Failed to broadcast task status change: #{e.message}")
    end

    def update_loop_task_counts
      # Update the parent loop's task counts whenever a task is created/updated/destroyed
      # Skip if ralph_loop is nil (happens during cascade delete)
      return unless ralph_loop.present?

      ralph_loop.update_columns(
        total_tasks: ralph_loop.ralph_tasks.count,
        completed_tasks: ralph_loop.ralph_tasks.where(status: "passed").count,
        failed_tasks: ralph_loop.ralph_tasks.where(status: "failed").count
      )
    end

    # ==================== Executor Finders ====================

    def find_matching_agent
      agents = ralph_loop.account.ai_agents.where(status: "active")
      required = required_capabilities || []
      return agents.first if required.empty?

      case capability_match_strategy
      when "all"
        agents.with_all_skills(required).first
      when "any"
        agents.with_any_skills(required).first
      when "weighted"
        agents.with_any_skills(required)
          .select("ai_agents.*, COUNT(DISTINCT ai_skills.slug) as skill_overlap")
          .order("skill_overlap DESC")
          .first
      else
        agents.with_any_skills(required).first
      end
    end

    def find_matching_pipeline
      scope = ralph_loop.account.devops_pipelines

      # Match pipelines by type or tags
      return scope.first if required_capabilities.blank?

      scope.where("tags && ARRAY[?]::varchar[]", required_capabilities).first || scope.first
    end

    def find_matching_container
      # Find container template that matches capabilities
      scope = Devops::ContainerTemplate.where(status: "active")

      return scope.first if required_capabilities.blank?

      scope.where("tags && ARRAY[?]::varchar[]", required_capabilities).first || scope.first
    end

    def find_via_a2a_discovery
      agent_cards = Ai::AgentCard.joins(:agent)
                                  .where(ai_agents: { account_id: ralph_loop.account_id, status: "active" })

      return agent_cards.first&.agent if required_capabilities.blank?

      matching_card = agent_cards.find do |card|
        slugs = card.agent&.skill_slugs || []
        case capability_match_strategy
        when "all"
          (required_capabilities - slugs).empty?
        when "any"
          (required_capabilities & slugs).any?
        else
          true
        end
      end

      matching_card&.agent
    end

    def find_community_agent
      scope = CommunityAgent.where(status: "active", visibility: %w[public unlisted])

      return scope.order(reputation_score: :desc).first if required_capabilities.blank?

      # Match community agents by skill slugs in capabilities JSON
      scope.where("capabilities->'skill_slugs' ?| array[:caps]", caps: required_capabilities)
           .order(reputation_score: :desc)
           .first
    end

    def find_human_reviewer
      # Find user with appropriate permissions for review
      # Default to account owner or first admin
      ralph_loop.account.users.joins(:roles)
                .where(roles: { name: %w[owner admin] })
                .first
    end

  end
end
