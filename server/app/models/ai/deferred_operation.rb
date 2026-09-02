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

    # What an executor may know about an operation while composing an APPROVAL
    # CARD. Deliberately NOT the operation itself (IMP-4a5094b22df0).
    #
    # The card path needs exactly one thing the request cannot supply: the
    # account the gate opened this operation in, so a label lookup can be
    # scoped to it. Handing over the operation would also hand over `params`,
    # `result` and `take_revealed_result!` — and the `deferred_operation: nil`
    # this replaced was, whatever else it cost, a FAIL-SAFE BACKSTOP: an
    # executor that reached for execution state from its preview got
    # NoMethodError on nil, which #preview's rescue turned into a generic card.
    # A leak through that channel could not silently start working.
    #
    # Passing the live operation would convert that self-limiting mistake into
    # a silent one, rendering execution state — possibly reveal-once material —
    # onto an approval card. This keeps the backstop by answering `account` and
    # nothing else: the same mistake still raises, and still degrades to a
    # generic card rather than disclosing.
    #
    # Duck-typed on `account` alone, which is already the shape executor base
    # classes accept on this keyword — extensions pass their own account-only
    # composition contexts through it — so nothing needed a new contract.
    class PreviewContext
      attr_reader :account

      def initialize(account)
        @account = account
      end
    end

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
      return Ai::ApprovalRequest::DISPATCH_NOOP unless pending?

      case request.status
      when "approved"
        execute_now!
      when "rejected"
        reject!
        release_composed_plan_step!
      when "expired"
        expire!
        release_composed_plan_step!
      else
        return Ai::ApprovalRequest::DISPATCH_NOOP
      end

      # Deliberately discards #execute_now!'s payload: the caller needs to know
      # THAT the branch ran, and the payload is legitimately nil or false for
      # some executors, so returning it would misreport a real execution as a
      # no-op. The per-operation detail lives on this row; the one-shot reveal
      # travels via #take_revealed_result!, not this return value.
      Ai::ApprovalRequest::DISPATCH_EXECUTED
    end

    # A composed provisioning step parked on THIS operation waits on the
    # DECISION, not only on a replay (APO-1f, IMP-117b34656921).
    #
    # The approved arm reaches Ai::Provisioning::SkillCompositionRunner through
    # the executor replay (#execute_now! -> the skill executor's own .execute).
    # Reject and expire run no executor at all, so without this door the step
    # would sit in SkillCompositionRunner::PARKED_STATUS forever: its mission
    # never advances (that requires every step `completed`) and its adaptation
    # never settles, which blocks every LATER adaptation on the same mission.
    # Before the parked state existed the step was recorded FAILED here, so this
    # keeps the pre-existing terminal behaviour for a refused approval.
    #
    # No result is handed over: the runner reads this row's settled status and
    # fails the step with the decision as its reason.
    #
    # Best-effort by construction — the decision has already been applied to
    # this row, and a resume that raises must not turn a recorded rejection into
    # an exception the approval callback surfaces. A missed step is recoverable
    # by re-invoking it; a lost decision is not. The runner is a no-op for the
    # common case where the operation belongs to no plan at all.
    def release_composed_plan_step!
      return unless defined?(::Ai::Provisioning::SkillCompositionRunner)

      ::Ai::Provisioning::SkillCompositionRunner.resume_parked_step(deferred_operation: self)
    rescue StandardError => e
      Rails.logger.error(
        "[DeferredOperation##{id}] composed-plan release failed: #{e.class}: #{e.message}"
      )
      nil
    end
    # An internal lane of #on_approval_decision, not a promise: nothing outside
    # this model may drive a plan resume from an operation.
    private :release_composed_plan_step!

    # Synchronous execution. Used by AutonomyGate for auto-approved operations
    # (so the calling controller gets the result inline) and by
    # on_approval_decision after a chain completes. The result is captured in
    # :result JSONB; row transitions to :completed (or :failed) atomically.
    def execute_now!
      approve! if pending?
      start_execution!
      assert_source_within_account!
      result_data = executor_constant.execute(params, deferred_operation: self)
      # Raw to the caller, redacted to the row. An executor that MINTS secret
      # material (federation propose mints a single-use acceptance token) is
      # contracted to reveal it exactly once — Ai::GatedActions renders this
      # return value on the :proceed branch, which is that one time. Persisting
      # the same value into :result would make this row a durable second copy
      # outside Vault. Sdwan::Executors::ProposeFederationPeer keeps only the
      # digest + expiry on the PEER, and is right about that — it just has no
      # say in what the gate does with what it hands back. `complete!` itself is
      # left alone so a caller passing its own payload still controls it.
      #
      # The APPROVAL path has no :proceed branch to render on (IMP-7b81ca22f661):
      # the requester got `pending: true` and left, and this method runs later
      # inside Ai::ApprovalRequest#notify_source_of_decision on an instance that
      # callback discards, so `result_data` below returns to nobody. Handing it
      # to the one-shot slot is what makes "exactly once" survive deferral —
      # zero reveals, not one, is what redaction alone would produce there.
      @revealed_result = result_data
      complete!(::Ai::SensitiveParams.filter(result_data || {}))
      result_data
    rescue StandardError => e
      Rails.logger.error("[DeferredOperation##{id}] execute_now! failed: #{e.class}: #{e.message}")
      fail!(e) if may_fail?
      raise
    end

    # Reveal-once handoff for an executor that MINTS secret material
    # (IMP-7b81ca22f661). Holds the raw return of the executor run that happened
    # on THIS instance, and only until someone takes it:
    #
    #   * in memory only — never a column, so a re-loaded row has nothing, and
    #     redaction-at-rest (:result stays filtered) is untouched;
    #   * cleared by the first read — a second reader of the same instance gets
    #     nil, so "exactly once" holds per execution rather than per caller;
    #   * unredacted, deliberately: this IS the one reveal, and the caller
    #     entitled to it is the one that resolved the gate.
    #
    # Set on both gate branches. On :proceed the caller already has the return
    # value inline and normally ignores this; on the approval path
    # Ai::ApprovalRequest#capture_revealed_result! is the only reader, because
    # the instance holding it dies with that callback.
    def take_revealed_result!
      value = @revealed_result
      @revealed_result = nil
      value
    end

    def executor_constant
      @executor_constant ||= executor_class.constantize
    end

    # The approval card's text, rendered by Ai::DeferredOperationApprovalContent
    # from the executor's own summary/impact.
    #
    # The ACCOUNT is threaded in, on the same keyword `execute` uses for the
    # operation (IMP-4a5094b22df0). It used to be dropped entirely, and that
    # was the root cause of a posture split in the executors: `perform`
    # resolved a row id through an account-anchored lookup while `summarize`
    # resolved the SAME id unscoped, because on the card path there was no
    # account to scope by. This row HAS one — the gate opened it in that
    # account — so a card can be anchored to it, and an executor no longer has
    # to choose between naming a row it cannot prove belongs to the approvers,
    # and naming nothing.
    #
    # `self` is deliberately NOT what goes through: see PreviewContext, which
    # carries the account and refuses everything else so that an executor
    # reaching for execution state from a preview still fails loud-to-safe.
    # That keeps reveal-once (IMP-7b81ca22f661) isolated by CONSTRUCTION rather
    # than by convention — `take_revealed_result!` is not on the object the
    # preview path holds, so no executor can call it, correctly or otherwise.
    def preview
      return { summary: action_category } unless executor_constant.respond_to?(:preview)

      executor_constant.preview(params, deferred_operation: PreviewContext.new(account))
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
      #
      # The SOURCE ROW is withheld for the same reason (IMP-dae0de4e562b). The
      # message used to read "<Type> <uuid> is not in account …", and while the
      # caller did name that pair themselves at gate time, echoing it back on
      # this branch and not on any other is what makes it an answer: the
      # assertion no-ops for a pair that resolves to nothing (see
      # #source_account_id), so "refused by name" versus "the executor's own
      # error" told a caller THAT the row exists. It travels further than the
      # raise, too — #fail! writes "#{e.class}: #{e.message}" into
      # error_message, a column the approvals surface serves back. So the raise
      # names only the action it refused; the pair and its owner stay in the log
      # above, which is where an operator investigating a real cross-tenant
      # attempt reads them.
      Rails.logger.warn(
        "[DeferredOperation##{id}] refused #{action_category}: #{source_type} #{source_id} " \
        "belongs to account #{owner_id}, not #{account_id}"
      )
      raise CrossAccountError,
            "refusing to execute #{action_category}: " \
            "its recorded source is not in account #{account_id}"
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
