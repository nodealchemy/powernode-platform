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
    # The plane the operation was gated against (Environment campaign, incr. 3).
    belongs_to :environment, class_name: "Ai::Environment", optional: true

    # Reserved key in the params column holding the sealed original of a
    # secret-bearing params hash (IMP-3d10c3c9439e). Never visible through the
    # `params` reader.
    SEALED_PARAMS_KEY = "_sealed_params"

    # Raised on replay when the sealed original cannot be produced: a missing
    # or blank envelope, one that will not decrypt, or one sealed for a
    # different operation. The executor is never run with masked values.
    class SealedParamsError < StandardError; end

    # Statuses whose params an executor can still replay.
    LIVE_STATUSES = %w[pending approved executing].freeze

    before_create :seal_secret_params
    validate :params_must_be_a_hash

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
          text = error.is_a?(Exception) ? "#{error.class}: #{error.message}" : error.to_s
          self.error_message = ::Ai::SensitiveParams.filter_text(text)
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

    # Polymorphic callback invoked from
    # `Ai::ApprovalRequest#abandon_stranded_dispatch!` (IMP-0213523480d1): the
    # request was approved, but the process died before its post-commit
    # dispatch started, so #on_approval_decision never ran and this row is
    # still `pending`. The reconciler has declared the request failed; this
    # settles the operation to match rather than leaving it pending forever.
    #
    # approve! then fail! rather than a new pending -> failed edge: the
    # decision WAS an approval, and `fail` deliberately admits only rows that
    # got that far. The executor never ran — the error says so, because
    # fail!'s executed_at stamp alone would read as though it had.
    #
    # Runs inside the request's claim transaction, under this row's lock; a
    # row that is no longer pending was settled by someone else and is left
    # alone.
    #
    # A parked composed-plan step is released once that transaction COMMITS,
    # never inside it: the release can compensate (a step's `rollback`
    # on_failure) and broadcast, and doing either before the settlement is
    # durable would let a failed commit repeat the compensation on the next
    # sweep, and let subscribers read a settlement that never happened. If the
    # process dies before the callback runs, the parked-step janitor
    # (SkillCompositionRunner.reap_parked_steps) reads this row's `failed`
    # status and releases the step itself.
    def on_dispatch_abandoned(error)
      settled = with_lock do
        next false unless pending?

        approve!
        fail!(error)
        true
      end
      ActiveRecord.after_all_transactions_commit { release_composed_plan_step! } if settled
      settled
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
        "[DeferredOperation##{id}] composed-plan release failed: #{e.class}: #{::Ai::SensitiveParams.filter_text(e.message)}"
      )
      nil
    end
    # An internal lane of #on_approval_decision, not a promise: nothing outside
    # this model may drive a plan resume from an operation.
    private :release_composed_plan_step!

    # Synchronous execution. Used by AutonomyGate for auto-approved operations
    # (so the calling controller gets the result inline) and by
    # on_approval_decision after a chain completes. The result is captured in
    # :result JSONB; row transitions to :completed (or :failed). Not atomic:
    # approve!, start_execution!, the executor's own writes, and complete!/
    # fail! are each their own commit (IMP-9ce0ed39c557 — on the approval path
    # this method now runs with no enclosing transaction at all, see below), so
    # an executor that writes durable state and then raises leaves that write
    # in place even though this row lands in :failed rather than :completed.
    def execute_now!
      approve! if pending?
      start_execution!
      assert_source_within_account!
      result_data = executor_constant.execute(replay_params, deferred_operation: self)
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
      # the requester got `pending: true` and left, and this method now runs
      # later from Ai::ApprovalRequest#dispatch_to_source!, itself deferred to
      # ActiveRecord.after_all_transactions_commit (IMP-9ce0ed39c557) — by the
      # time it runs, the decision's own transaction has already committed and
      # nothing wraps this call, so `result_data` below returns to nobody, and
      # this instance is a fresh find_by, not the one the callback loaded
      # pre-commit. Handing it to the one-shot slot is what makes "exactly
      # once" survive deferral — zero reveals, not one, is what redaction
      # alone would produce there.
      #
      # Only a result that HOLDS secret material is revealed: the filter masking
      # something is the same test that keeps it out of :result. A plain return
      # (a policy write, a terminate) has nothing to show once, and revealing it
      # sent every approver through a "shown once — save it now" modal.
      filtered = ::Ai::SensitiveParams.filter(result_data || {})
      reveal_once = filtered != (result_data || {})
      @revealed_result = result_data if reveal_once
      text_filtered = filter_envelope_text(filtered)
      complete!(text_filtered)
      # The caller of :proceed is the requester: it gets the executor's return
      # exactly as produced (the reveal-once contract for a minted secret
      # included). Only the STORED envelope is redacted.
      result_data
    rescue StandardError => e
      Rails.logger.error("[DeferredOperation##{id}] execute_now! failed: #{e.class}: " \
                         "#{::Ai::SensitiveParams.filter_text(e.message)}")
      fail!(e) if may_fail?
      raise
    ensure
      # The caller's original must not outlive the replay on this instance.
      @unsealed_params = nil
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

    # The params as every reader sees them: secret-looking values masked and
    # the sealed envelope hidden. The original is only ever reachable through
    # #replay_params, on the executor-replay path.
    # Filtered on every read, not only at write, so a row stored before sealing
    # existed (plaintext in the column) is masked too. Idempotent on masked values.
    def params
      stored = super
      return stored unless stored.is_a?(Hash)

      ::Ai::SensitiveParams.filter(stored.except(SEALED_PARAMS_KEY))
    end

    # Dry-run-by-default backfill for rows written before the gate sealed
    # params (IMP-3d10c3c9439e). Live rows (an executor may still replay them)
    # are sealed and masked; terminal rows are masked only. Rows already
    # carrying an envelope are skipped, unless `reseal` re-encrypts the live ones
    # under the current key (run before dropping an old encryption key).
    # Returns the counts.
    def self.backfill_params_seal(dry_run: true, reseal: false)
      counts = { sealed: 0, masked: 0, skipped: 0, resealed: 0, failed: 0, dry_run: dry_run }
      find_each do |op|
        stored = op[:params]
        # Key rotation: ar_encryption:re_encrypt_all cannot reach the envelope,
        # so live sealed rows are re-encrypted under the current key here.
        if reseal && stored.is_a?(Hash) && stored.key?(SEALED_PARAMS_KEY) && LIVE_STATUSES.include?(op.status)
          begin
            # Decrypts in a dry run too, so an unopenable envelope is reported
            # before anything is written. One bad row never stops the sweep.
            fresh = op.send(:sealed_params_for, op.send(:replay_params))
            op.update_columns(params: fresh) unless dry_run
            counts[:resealed] += 1
          rescue SealedParamsError
            counts[:failed] += 1
          end
          next
        end

        unless stored.is_a?(Hash) && !stored.key?(SEALED_PARAMS_KEY) &&
               ::Ai::SensitiveParams.filter(stored) != stored
          counts[:skipped] += 1
          next
        end

        if LIVE_STATUSES.include?(op.status)
          counts[:sealed] += 1
          op.update_columns(params: op.send(:sealed_params_for, stored)) unless dry_run
        else
          counts[:masked] += 1
          op.update_columns(params: ::Ai::SensitiveParams.filter(stored)) unless dry_run
        end
      end
      counts
    end

    def executor_constant
      @executor_constant ||= executor_class.constantize
    end

    # L9: why `approver`'s approval must not complete this operation's request,
    # or nil. Ai::ApprovalRequest#record_decision! asks before it records a
    # completing approval. The executor answers, since only it knows who its
    # replay runs as, and it gets the account alone, as #preview does. An
    # operation no longer pending runs nothing on approval, so no one is
    # refused for it; an executor class that no longer resolves is refused by
    # its replay instead.
    def approval_decider_refusal(approver)
      return nil unless pending?

      executor = executor_class.to_s.safe_constantize
      return nil unless executor.respond_to?(:approval_decider_refusal)

      executor.approval_decider_refusal(params, deferred_operation: PreviewContext.new(account), approver: approver)
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
      { summary: action_category, error: "preview failed: #{::Ai::SensitiveParams.filter_text(e.message)}" }
    end

    private

    # The key-based filter cannot see inside a string, and an executor's failed
    # envelope carries free text under `error`/`message` that can quote the very
    # params it masks (IMP-f8e6bbc5e3bb). Only those two top-level string
    # members are rewritten; the envelope's shape is untouched.
    ENVELOPE_TEXT_KEYS = %w[error message details stderr output].freeze

    def filter_envelope_text(node, inside: false)
      case node
      when ::Hash
        node.each_with_object(node.class.new) do |(key, value), out|
          out[key] = filter_envelope_text(value, inside: inside || ENVELOPE_TEXT_KEYS.include?(key.to_s))
        end
      when ::Array then node.map { |value| filter_envelope_text(value, inside: inside) }
      # Only free text under an error-ish member, only the secret patterns, no
      # truncation: every other leaf is byte-identical to what the executor said.
      when ::String then inside ? ::Ai::SensitiveParams.filter_text(node, truncate: false) : node
      else node
      end
    end

    # Reveal-on-replay for the params, the counterpart of the reveal-once
    # handling of :result above. The gate hands over caller-supplied params that
    # may carry secrets; the column keeps only the masked view plus the original
    # sealed with ActiveRecord::Encryption (the house keys, so the documented
    # rotation applies), and the executor, which replays its own params, is the
    # only reader that gets the original back. Anything that stops the original
    # being produced raises SealedParamsError: masked values are never replayed.
    #
    # Rotation: ar_encryption:re_encrypt_all only walks `encrypts` attributes and
    # does not reach this envelope; the previous-keys read fallback still opens
    # it, and .backfill_params_seal(reseal: true) re-encrypts live rows under the
    # current key (runbook step 3b in config/initializers/encryption.rb). Terminal
    # sealed rows keep a decryptable envelope until their key is dropped, by
    # design: nothing replays them, and sealing them is cheaper than a purge.
    def replay_params
      # The instance that opened the gate still holds the caller's own hash, so
      # key types match what an unsealed operation hands over.
      return @unsealed_params if @unsealed_params

      stored = self[:params]
      # No envelope: replay the RAW column, never the masked reader. A legacy
      # row (pre-backfill) or one whose keys became sensitive after the operator
      # widened ai_sensitive_param_keys must not replay "[FILTERED]".
      return raw_params(stored) unless stored.is_a?(Hash) && stored.key?(SEALED_PARAMS_KEY)

      unseal_params(stored[SEALED_PARAMS_KEY])
    end

    # The raw column minus any envelope key (of any key type). A value that is
    # exactly the mask means the original was lost (envelope stripped from a live
    # row): masked values are never replayed.
    def raw_params(stored)
      return params unless stored.is_a?(Hash)

      raw = stored.reject { |key, _| key.to_s == SEALED_PARAMS_KEY }
      if contains_mask?(raw)
        raise SealedParamsError, "params for #{action_category} hold masked values and no sealed original"
      end

      raw
    end

    def contains_mask?(value)
      case value
      when Hash then value.each_value.any? { |v| contains_mask?(v) }
      when Array then value.any? { |v| contains_mask?(v) }
      else value == ::Ai::SensitiveParams::MASK
      end
    end

    def unseal_params(blob)
      raise SealedParamsError, "sealed params for #{action_category} are missing" if blob.blank?

      plain = ::ActiveRecord::Encryption.encryptor.decrypt(blob)
      raise SealedParamsError, "sealed params for #{action_category} are empty" if plain.blank?

      envelope = JSON.parse(plain)
      unless envelope.is_a?(Hash) && envelope["context"] == seal_context
        raise SealedParamsError, "sealed params for #{action_category} do not match this operation's context"
      end

      envelope.fetch("params")
    rescue SealedParamsError
      raise
    rescue StandardError
      # Class only: a decrypt error's message can carry key material.
      raise SealedParamsError, "sealed params for #{action_category} could not be opened"
    end

    def params_must_be_a_hash
      raw = self[:params]
      return if raw.nil? || raw.is_a?(Hash) || raw.respond_to?(:to_unsafe_h)

      errors.add(:params, "must be a Hash")
    end

    def seal_secret_params
      raw = self[:params]
      raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      return unless raw.is_a?(Hash)

      # Whatever its key type: a caller-planted envelope must never survive.
      raw = raw.reject { |key, _| key.to_s == SEALED_PARAMS_KEY }
      if ::Ai::SensitiveParams.filter(raw) == raw
        self[:params] = raw
        return
      end

      @unsealed_params = raw
      self[:params] = sealed_params_for(raw)
    end

    # The stored form: masked view plus the sealed original. The binding context
    # rides INSIDE the ciphertext and is checked after decrypt. The row id is
    # not part of it: the id is assigned by the database default at INSERT, after
    # this runs. Consequence, stated plainly: an envelope copied between two rows
    # with the SAME account, executor and action category is accepted. That takes
    # database write access, which already lets an attacker rewrite params.
    def sealed_params_for(raw)
      envelope = { context: seal_context, params: raw }.to_json
      ::Ai::SensitiveParams.filter(raw).merge(
        SEALED_PARAMS_KEY => ::ActiveRecord::Encryption.encryptor.encrypt(envelope)
      )
    end

    def seal_context
      { "account_id" => account_id.to_s, "executor_class" => executor_class.to_s,
        "action_category" => action_category.to_s }
    end

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
