# frozen_string_literal: true

module Ai
  class TeamExecution < ApplicationRecord
    self.table_name = "ai_team_executions"

    STATUSES = %w[pending running paused completed failed cancelled timeout awaiting_approval].freeze

    # Associations
    belongs_to :account
    belongs_to :agent_team, class_name: "Ai::AgentTeam", foreign_key: "agent_team_id"
    belongs_to :triggered_by, class_name: "User", foreign_key: "triggered_by_id", optional: true
    belongs_to :conversation, class_name: "Ai::Conversation", foreign_key: "ai_conversation_id", optional: true
    belongs_to :approval_decided_by, class_name: "User", foreign_key: "approval_decided_by_id", optional: true
    belongs_to :mission, class_name: "Ai::Mission", foreign_key: "mission_id", optional: true

    has_many :tasks, class_name: "Ai::TeamTask", foreign_key: :team_execution_id, dependent: :destroy
    has_many :messages, class_name: "Ai::TeamMessage", foreign_key: :team_execution_id, dependent: :destroy

    # Validations
    validates :execution_id, presence: true, uniqueness: true
    validates :status, inclusion: { in: STATUSES }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :active, -> { where(status: %w[pending running paused awaiting_approval]) }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }

    # Callbacks
    before_validation :generate_execution_id, on: :create

    # Status transitions
    def start!
      update!(status: "running", started_at: Time.current)
    end

    def pause!
      update!(status: "paused")
    end

    def resume!
      update!(status: "running")
    end

    def complete!(result = {})
      update!(
        status: "completed",
        completed_at: Time.current,
        duration_ms: calculate_duration,
        output_result: result,
        termination_reason: "completed"
      )
    end

    def fail!(reason)
      update!(
        status: "failed",
        completed_at: Time.current,
        duration_ms: calculate_duration,
        termination_reason: reason
      )
    end

    def cancel!(reason = "user_cancelled")
      update!(
        status: "cancelled",
        completed_at: Time.current,
        duration_ms: calculate_duration,
        termination_reason: reason
      )
    end

    def timeout!
      update!(
        status: "timeout",
        completed_at: Time.current,
        duration_ms: calculate_duration,
        termination_reason: "timeout"
      )
    end

    # Status checks
    def active?
      %w[pending running paused awaiting_approval].include?(status)
    end

    def awaiting_approval?
      status == "awaiting_approval"
    end

    def finished?
      %w[completed failed cancelled timeout].include?(status)
    end

    def await_approval!(conv)
      update!(
        status: "awaiting_approval",
        completed_at: Time.current,
        duration_ms: calculate_duration,
        ai_conversation_id: conv.id
      )
    end

    # Task management
    def update_task_counts!
      update!(
        tasks_total: tasks.count,
        tasks_completed: tasks.where(status: "completed").count,
        tasks_failed: tasks.where(status: "failed").count
      )
    end

    def progress_percentage
      return 0 if tasks_total.zero?

      ((tasks_completed.to_f / tasks_total) * 100).round(2)
    end

    # Keys under `metadata` tracking retry-enqueue idempotency for this
    # execution. Reused rather than a new column/table, since the retried
    # execution itself is created asynchronously by the worker and never
    # exists synchronously for the controller to key a claim off.
    #
    # Two-phase, not a single flag, so a request that only WON the claim (but
    # hasn't enqueued yet) can't be read by a concurrent loser as "queued":
    #   enqueuing -> mark_retry_queued! / mark_retry_unknown!, or the claim
    #   is released outright on a definite non-enqueue (see
    #   claim_retry!/release_retry_claim! callers in
    #   AgentTeamExecutionsController#retry_execution).
    RETRY_STATE_KEY = "retry_state"
    RETRY_QUEUED_AT_KEY = "retry_queued_at"
    RETRY_JOB_ID_KEY = "retry_job_id"

    RETRY_STATE_ENQUEUING = "enqueuing"
    RETRY_STATE_QUEUED = "queued"
    RETRY_STATE_UNKNOWN = "unknown"

    # Margin added on top of WorkerJobService's own request timeout when
    # deciding whether an "enqueuing" claim is stale rather than genuinely
    # in flight. The process that won the claim can die (deploy, OOM, ...)
    # before ever reaching make_worker_request's own timeout, which would
    # otherwise strand the row in "enqueuing" forever and 409 every later
    # retry attempt. Not itself a business/spend budget — a technical
    # allowance for scheduling jitter on top of a real timeout value.
    RETRY_STALE_MARGIN_SECONDS = 60

    def self.retry_enqueuing_stale_after_seconds
      WorkerJobService.request_timeout_seconds + RETRY_STALE_MARGIN_SECONDS
    end

    # Atomically claim the retry slot for this execution: at most one caller
    # ever wins, including under a concurrent double-click. The UPDATE's
    # WHERE clause only matches while retry_state is absent, and Postgres
    # serializes concurrent UPDATEs against the same row — the second
    # writer's statement blocks until the first commits, then re-evaluates
    # its WHERE against the now-committed row and matches nothing. This is a
    # single conditional UPDATE, not a check-then-act race.
    #
    # Always reloads (win or lose), so a losing caller sees the winner's
    # retry_state/retry_queued_at rather than its own stale pre-claim read.
    # Returns true iff THIS call won the claim.
    def claim_retry!
      claimed_at = Time.current
      updated = self.class
        .where(id: id)
        .where("metadata->>'#{RETRY_STATE_KEY}' IS NULL")
        .update_all(
          [ "metadata = COALESCE(metadata, '{}'::jsonb) || " \
            "jsonb_build_object(?::text, ?::text, ?::text, ?::text), updated_at = ?",
            RETRY_STATE_KEY, RETRY_STATE_ENQUEUING, RETRY_QUEUED_AT_KEY, claimed_at.iso8601, claimed_at ]
        )
      reload
      updated.positive?
    end

    # Release a claim made by this caller after a DEFINITE non-enqueue (the
    # request never reached the worker, or the worker explicitly rejected
    # it) — never call this for an ambiguous outcome, or a client retry could
    # queue a second execution on top of one that already exists. Clears
    # both retry keys so a later claim starts clean; leaves retry_job_id (set
    # only after a real success) alone, though it should never be present
    # here. No reload — callers re-raise immediately and don't read the
    # execution's retry state afterward.
    def release_retry_claim!
      self.class.where(id: id).update_all(
        [ "metadata = metadata - ? - ?, updated_at = ?", RETRY_STATE_KEY, RETRY_QUEUED_AT_KEY, Time.current ]
      )
    end

    # Same unconditional "merge into metadata via update_all" idiom as
    # Ai::Provisioning::SkillCompositionRunner#stamp_dispatched! — appropriate
    # here because the CAS already happened in claim_retry!; this only
    # advances a claim this caller already won. The `retry_state = enqueuing`
    # WHERE clause is defence-in-depth, not the primary guarantee (that's
    # claim_retry!'s CAS) — it just stops this from clobbering a state that
    # somehow isn't "enqueuing" anymore (e.g. mis-sequenced calls) rather
    # than silently overwriting it.
    def mark_retry_queued!(job_id: nil)
      payload = { RETRY_STATE_KEY => RETRY_STATE_QUEUED }
      payload[RETRY_JOB_ID_KEY] = job_id.to_s if job_id.present?
      self.class.where(id: id)
        .where("metadata->>'#{RETRY_STATE_KEY}' = '#{RETRY_STATE_ENQUEUING}'")
        .update_all(
          [ "metadata = COALESCE(metadata, '{}'::jsonb) || ?::jsonb, updated_at = ?", payload.to_json, Time.current ]
        )
      reload
    end

    # The worker outcome is genuinely unknown (e.g. a read timeout or 5xx
    # after the request was sent) — keep the claim so a client retry can't
    # queue a second execution on top of a possible first one. Same
    # defence-in-depth WHERE guard as mark_retry_queued!.
    def mark_retry_unknown!
      self.class.where(id: id)
        .where("metadata->>'#{RETRY_STATE_KEY}' = '#{RETRY_STATE_ENQUEUING}'")
        .update_all(
          [ "metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(?::text, ?::text), updated_at = ?",
            RETRY_STATE_KEY, RETRY_STATE_UNKNOWN, Time.current ]
        )
      reload
    end

    def retry_state
      metadata && metadata[RETRY_STATE_KEY]
    end

    def retry_queued_at
      metadata && metadata[RETRY_QUEUED_AT_KEY]
    end

    def retry_job_id
      metadata && metadata[RETRY_JOB_ID_KEY]
    end

    # True when this execution's claim is stuck at "enqueuing" for longer
    # than a real worker request could still be in flight — i.e. the process
    # that won the claim almost certainly died before it could ever mark the
    # outcome queued/unknown/released. Never re-claims (that could create a
    # duplicate if the original request is in fact still running); callers
    # should treat this as "unknown", not as "safe to retry".
    def retry_enqueuing_stale?
      return false unless retry_state == RETRY_STATE_ENQUEUING

      queued_at = retry_queued_at
      return false if queued_at.blank?

      Time.iso8601(queued_at) < self.class.retry_enqueuing_stale_after_seconds.seconds.ago
    rescue ArgumentError
      false
    end

    # Messaging
    def record_message!
      increment!(:messages_exchanged)
    end

    # Resource tracking
    def add_tokens!(count)
      increment!(:total_tokens_used, count)
    end

    def add_cost!(amount)
      update!(total_cost_usd: total_cost_usd + amount)
    end

    # Shared memory
    def get_memory(key)
      shared_memory[key]
    end

    def set_memory(key, value)
      update!(shared_memory: shared_memory.merge(key => value))
    end

    def clear_memory(key)
      new_memory = shared_memory.except(key)
      update!(shared_memory: new_memory)
    end

    private

    def generate_execution_id
      self.execution_id ||= "exec_#{SecureRandom.hex(12)}"
    end

    def calculate_duration
      return nil unless started_at.present?

      ((Time.current - started_at) * 1000).to_i
    end
  end
end
