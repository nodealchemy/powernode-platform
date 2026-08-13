# frozen_string_literal: true

module Ai
  # Captures a mutating operation that may be auto-approved or deferred for
  # human approval via the AutonomyGate. Every operation gated through
  # `Ai::AutonomyGate.evaluate` produces a row here — auto-approved ones get
  # status: "approved" immediately and execute synchronously; pending ones
  # link to an `Ai::ApprovalRequest` and execute via the worker job once the
  # chain completes.
  class DeferredOperation < ApplicationRecord
    self.table_name = "ai_deferred_operations"

    include AASM

    # Raised when a gated operation would act on a record outside the account
    # it was authorised for. Extensions raise it too, from their own executor
    # base class, so both tenancy anchors surface one error identity.
    class CrossAccountError < StandardError; end

    STATUSES = %w[pending approved rejected expired executing completed failed].freeze

    belongs_to :account
    belongs_to :approval_request, class_name: "Ai::ApprovalRequest", optional: true
    belongs_to :requested_by, class_name: "User", optional: true
    belongs_to :ai_agent, class_name: "Ai::Agent", optional: true

    validates :action_category, presence: true
    validates :executor_class,  presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :pending,    -> { where(status: "pending") }
    scope :approved,   -> { where(status: "approved") }
    scope :rejected,   -> { where(status: "rejected") }
    scope :completed,  -> { where(status: "completed") }
    scope :failed,     -> { where(status: "failed") }
    scope :for_source, ->(type, id) { where(source_type: type, source_id: id) }
    scope :recent,     -> { order(created_at: :desc) }

    aasm column: :status, whiny_transitions: true do
      state :pending, initial: true
      state :approved
      state :rejected
      state :expired
      state :executing
      state :completed
      state :failed

      event :approve do
        transitions from: :pending, to: :approved
      end

      event :reject do
        transitions from: :pending, to: :rejected
      end

      event :expire do
        transitions from: :pending, to: :expired
      end

      event :start_execution do
        transitions from: :approved, to: :executing
      end

      event :complete do
        transitions from: :executing, to: :completed
        before do |result_data = {}|
          self.result = result_data
          self.executed_at = Time.current
        end
      end

      event :fail do
        transitions from: %i[approved executing], to: :failed
        before do |error = nil|
          self.error_message = error.is_a?(Exception) ? "#{error.class}: #{error.message}" : error.to_s
          self.executed_at ||= Time.current
        end
      end
    end

    # Polymorphic callback invoked from `Ai::ApprovalRequest#notify_source_of_decision`
    # when source_type == "Ai::DeferredOperation". Approval flips status and
    # invokes the executor synchronously; rejection/expiry terminates.
    #
    # Synchronous because executors live in the server process and most
    # operations are fast (record updates, model destroys). Long-running
    # ops (K3s bootstrap, etc.) should delegate to System::Task internally
    # so the actual work happens in the worker via the existing dispatch.
    def on_approval_decision(request)
      return unless pending?

      case request.status
      when "approved"
        execute_now!
      when "rejected"
        reject!
      when "expired"
        expire!
      end
    end

    # Synchronous execution. Used by AutonomyGate for auto-approved operations
    # (so the calling controller gets the result inline) and by
    # on_approval_decision after a chain completes. The result is captured in
    # :result JSONB; row transitions to :completed (or :failed) atomically.
    def execute_now!
      approve! if pending?
      start_execution!
      assert_source_within_account!
      result_data = executor_constant.execute(params, deferred_operation: self)
      complete!(result_data || {})
      result_data
    rescue StandardError => e
      Rails.logger.error("[DeferredOperation##{id}] execute_now! failed: #{e.class}: #{e.message}")
      fail!(e) if may_fail?
      raise
    end

    def executor_constant
      @executor_constant ||= executor_class.constantize
    end

    def preview
      executor_constant.respond_to?(:preview) ? executor_constant.preview(params) : { summary: action_category }
    rescue StandardError => e
      { summary: action_category, error: "preview failed: #{e.message}" }
    end

    private

    # Re-anchor the recorded source to THIS operation's account immediately
    # before the executor runs. The gate stores caller-supplied params verbatim
    # and this method replays them with no re-validation — for a deferred
    # operation, hours after the request — while executors are deliberately
    # unscoped at the point of dispatch, trusting the call site that opened the
    # gate.
    #
    # It covers exactly ONE pair: the source_type/source_id the gate recorded.
    # It is not a general tenancy check, and deliberately no-ops for callers
    # that record no source at all, or a source that is provenance rather than
    # the row about to be mutated. Rows an executor resolves for itself out of
    # `params` are anchored by the executor's own params-level scoping, at the
    # point it dereferences them. Two anchors, two moments: this one re-checks
    # the recorded pair just before the replay; the executor's covers what it
    # actually touches.
    #
    # Deliberately generic: core must not know any extension's models, so the
    # source is resolved by name and asserted only when the record actually
    # carries an account anchor.
    def assert_source_within_account!
      owner_id = source_account_id
      return if owner_id.nil? || owner_id == account_id

      # The owner's account id is logged, never raised: on the auto-approve path
      # Ai::AutonomyGate rescues and renders e.message straight back to the
      # caller, so naming the owner would answer a cross-tenant probe.
      Rails.logger.warn(
        "[DeferredOperation##{id}] refused #{action_category}: #{source_type} #{source_id} " \
        "belongs to account #{owner_id}, not #{account_id}"
      )
      raise CrossAccountError,
            "#{source_type} #{source_id} is not in account #{account_id} — " \
            "refusing to execute #{action_category}"
    end

    # nil means "no assertion can be made", which is NOT the same as "allowed":
    # a blank source pair, a source_type that names no model (the column is free
    # text), a row that has since been deleted, or a model with no account of
    # its own. Each is left to the executor, which fails on its own terms.
    def source_account_id
      return nil if source_type.blank? || source_id.blank?

      klass = source_type.safe_constantize
      return nil unless klass.respond_to?(:column_names) && klass.respond_to?(:find_by)

      # `find_by(id:)` is answerable only by a class backed by a real table that
      # actually carries an `id`, and this free-text column admits names where
      # neither holds: an abstract model raises TableNotSpecified, and a model
      # keyed on a pair (UserRole, RolePermission, WorkerRole) raises
      # PG::UndefinedColumn — which additionally poisons the surrounding
      # transaction, so the `fail!` in #execute_now!'s rescue raises in turn and
      # strands the row in :executing with no error recorded. Both are facts
      # about the class, knowable without querying, so they reach the same nil
      # as a miss instead of a raise.
      #
      # Checked rather than rescued: TableNotSpecified is not a StatementInvalid,
      # while ConnectionFailed is one — a rescue narrow enough to leave a
      # database blip alone would not catch the abstract case, and one wide
      # enough to catch it would silently disarm the anchor on that blip.
      # (A malformed id needs no guard: Rails casts a non-uuid to nil before it
      # reaches PostgreSQL, so the query degrades to `id IS NULL`.)
      return nil unless klass.respond_to?(:table_exists?) && klass.table_exists?
      return nil unless klass.column_names.include?("id")

      record = klass.find_by(id: source_id)
      return nil if record.nil?

      return record.account_id if record.respond_to?(:account_id)

      record.account&.id if record.respond_to?(:account)
    end
  end
end
