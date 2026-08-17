# frozen_string_literal: true

module Ai
  class ApprovalRequest < ApplicationRecord
    self.table_name = "ai_approval_requests"

    # Associations
    belongs_to :account
    belongs_to :approval_chain, class_name: "Ai::ApprovalChain"
    belongs_to :requested_by, class_name: "User", optional: true

    has_many :decisions, class_name: "Ai::ApprovalDecision", dependent: :destroy

    # The reply vocabulary of the polymorphic #on_approval_decision dispatch
    # (IMP-5547989e2bbd). An implementation returns DISPATCH_EXECUTED when it
    # actually ran its decision branch and DISPATCH_NOOP when it deliberately
    # did nothing — the source is no longer pending, already executed,
    # cancelled, or no longer parked at the gate this request was opened for.
    #
    # It exists because "the dispatch returned without raising" and "the
    # dispatch did something" are not the same statement, and #notify_source_of_decision
    # used to declare "succeeded" on the first while claiming the second. Every
    # implementation's no-op is an early `return` in a guard, so a source that
    # did nothing was indistinguishable from one that executed — a FALSE
    # SUCCESS on the very surface IMP-4bbb4227ac8a built to end false silence.
    #
    # Reported rather than inferred: the acting arm's own return value is
    # arbitrary (Ai::DeferredOperation#on_approval_decision returns
    # #execute_now!'s payload, which is legitimately nil or false for some
    # executors), so truthiness would misread real executions as no-ops and
    # trade one false statement for another.
    #
    # Unrecognised replies — a source written before this contract, or a test
    # double — are treated as "cannot say", and a request whose source cannot
    # say leaves execution_status nil. That is the DEFINED state for "nothing
    # to declare" (see #notify_source_of_decision), so the safe default lands on
    # an existing, honest value rather than on an assertion nobody verified.
    # Migrated sources: Ai::DeferredOperation, Ai::Mission, Ai::CampaignLand,
    # Ai::AgentProposal, Ai::ImprovementRecommendation — the complete set that
    # implements the hook (no extension does).
    DISPATCH_EXECUTED = :executed
    DISPATCH_NOOP = :noop

    # Validations
    validates :request_id, presence: true, uniqueness: true
    validates :status, presence: true, inclusion: { in: %w[pending approved rejected expired cancelled] }
    validates :execution_status, inclusion: { in: %w[succeeded failed] }, allow_nil: true

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :approved, -> { where(status: "approved") }
    scope :rejected, -> { where(status: "rejected") }
    scope :expired, -> { where(status: "expired") }
    scope :active, -> { pending.where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :for_source, ->(type, id) { where(source_type: type, source_id: id) }
    scope :for_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }

    # Callbacks
    before_validation :set_request_id, on: :create
    after_create  :fan_out_step_notifications, if: :pending?
    after_update  :notify_source_of_decision, if: :saved_change_to_status?
    after_update  :fan_out_step_notifications, if: :saved_change_to_current_step?

    # Methods
    def pending?
      status == "pending"
    end

    def approved?
      status == "approved"
    end

    def rejected?
      status == "rejected"
    end

    def expired?
      expires_at.present? && expires_at < Time.current
    end

    def current_step_info
      step_statuses[current_step] if step_statuses.present?
    end

    # Typed approver specs supported:
    #   "*"                                              — any active user
    #   "<user_uuid>"                                    — specific user (legacy)
    #   { "type" => "user",       "value" => "<uuid>" } — specific user
    #   { "type" => "permission", "value" => "<name>" } — anyone with the permission
    #   { "type" => "role",       "value" => "<name>" } — anyone with the role
    def can_approve?(user)
      return false unless pending?
      return false if expired?

      step_info = current_step_info
      return false unless step_info

      approvers = step_info["approvers"] || []
      approvers.any? { |spec| approver_matches?(spec, user) }
    end

    def record_decision!(approver:, decision:, comments: nil, conditions: {})
      return false unless can_approve?(approver)

      decisions.create!(
        approver: approver,
        step_number: current_step,
        decision: decision,
        comments: comments,
        conditions: conditions
      )

      process_decision(decision)
    end

    def check_expiration!
      return unless pending? && expired?

      case approval_chain.timeout_action
      when "approve"
        approve!
      when "reject"
        reject!
      when "escalate"
        escalate!
      else
        update!(status: "expired")
      end
    end

    # Resolve the request outright, bypassing the per-step approver tally: the
    # terminal transitions #process_decision and #check_expiration! converge on,
    # and the operator override for a caller that holds the row.
    #
    # PUBLIC API (IMP-7836ec7a974d) — these lived below `private`, so
    # `respond_to?(:approve!)` was false at every external call site and the one
    # caller guarding on that predicate (Ai::CampaignLand#operator_approve!)
    # never took its governed branch. Resolving the row is what cascades: the
    # status flip fires #notify_source_of_decision, which calls the source's
    # #on_approval_decision. `escalate!` stays private — only #check_expiration!
    # applies it.
    def approve!
      update!(status: "approved", completed_at: Time.current)
      approval_chain.increment!(:usage_count)
    end

    def reject!
      update!(status: "rejected", completed_at: Time.current)
    end

    # Reveal-once handoff (IMP-7b81ca22f661). #notify_source_of_decision runs
    # the source's executor on an instance it loaded itself and drops on return,
    # so an executor that MINTS secret material would mint it into nothing: the
    # requester left with `pending: true`, and the stored result is redacted.
    #
    # This instance is the one the deciding caller holds (the controller/tool
    # passes it into the workflow service, which resolves it in place), so it is
    # the only object that spans the executor run and the decision RESPONSE.
    # Same one-shot contract as the source's slot: in memory only, so a
    # re-loaded row yields nil, and cleared by the first read.
    def take_revealed_result!
      value = @revealed_result
      @revealed_result = nil
      value
    end

    private

    def approver_matches?(spec, user)
      case spec
      when "*" then true
      when String then spec == user.id.to_s
      when Hash
        case spec["type"]
        when "user"       then spec["value"] == user.id.to_s
        when "permission" then user.respond_to?(:has_permission?) && user.has_permission?(spec["value"])
        when "role"       then user.respond_to?(:has_role?) && user.has_role?(spec["value"])
        else false
        end
      else false
      end
    end

    def set_request_id
      self.request_id ||= UUID7.generate
    end

    # IMP-4bbb4227ac8a — the rescue below used to only log, which made every
    # post-approval executor failure invisible: the request stayed "approved",
    # the operation failed (or stranded), and no operator-visible signal existed
    # anywhere. Observability only — approval semantics are unchanged and
    # nothing retries: the outcome of the dispatch is DECLARED on this row
    # (execution_status/execution_error) and, on failure, emitted as an
    # Ai::ExecutionEvent (surfaced via platform.recent_events).
    #
    # execution_status stays nil unless an on_approval_decision dispatch for an
    # *approved* request actually ran: "succeeded" means the source REPORTED
    # that it ran its decision branch (DISPATCH_EXECUTED — for
    # Ai::DeferredOperation sources that means the executor completed, and its
    # own row carries the per-operation detail), "failed" means the dispatch
    # raised. Rejected/expired notifications keep the prior log-only behavior —
    # nothing executed, so there is no execution outcome to declare.
    #
    # IMP-5547989e2bbd made the first of those true rather than merely claimed.
    # A source whose #on_approval_decision no-ops (already executed, cancelled,
    # no longer at this gate) returns without raising, and this used to stamp
    # "succeeded" for it — a false success on the anti-false-silence surface.
    # Such a dispatch now leaves execution_status nil, which is the same state
    # a rejected decision leaves and means the same thing: nothing executed.
    # See DISPATCH_EXECUTED / DISPATCH_NOOP for the reply vocabulary and why the
    # source reports instead of the caller guessing.
    #
    # Known residual, deliberately out of scope here: this callback fires
    # pre-commit inside the status-flip's own transaction, so an executor
    # failing at the DATABASE level (RecordNotUnique/StatementInvalid) aborts
    # that transaction and the declaration writes below no-op — and the status
    # flip itself rolls back with them. Declaring that class requires either a
    # savepoint around the dispatch (which would change what an executor's
    # partial writes and the operation's own fail! survive) or an off-
    # transaction sink; both alter semantics this change is pinned not to touch.
    def notify_source_of_decision
      return unless %w[approved rejected expired].include?(status)
      return if source_type.blank? || source_id.blank?

      klass = source_type.safe_constantize
      return unless klass.respond_to?(:find_by)

      source = klass.find_by(id: source_id)
      return unless source.respond_to?(:on_approval_decision)

      outcome = source.on_approval_decision(self)
      capture_revealed_result!(source)
      declare_dispatch_outcome!(outcome)
    rescue StandardError => e
      Rails.logger.error("[ApprovalRequest##{id}] notify_source_of_decision failed: #{e.message}")
      declare_execution_failure!(e) if approved?
    end

    # Take the source's one-shot reveal onto this instance before `source` goes
    # out of scope. Sources are polymorphic and most (Ai::CampaignLand, Ai::Agent)
    # run no executor at all, so the slot is optional — but the predicate has to
    # be answered against the real receiver, not assumed: #take_revealed_result!
    # is public on Ai::DeferredOperation precisely so this respond_to? is true.
    #
    # Never raises: a source that answers the name with something surprising
    # must not take down the decision it is a side effect of.
    def capture_revealed_result!(source)
      return unless source.respond_to?(:take_revealed_result!)

      @revealed_result = source.take_revealed_result!
    rescue StandardError => e
      Rails.logger.error("[ApprovalRequest##{id}] capture_revealed_result! failed: #{e.message}")
    end

    # Stamp the declared outcome from what the source REPORTED, rather than from
    # the mere absence of an exception (IMP-5547989e2bbd).
    #
    # Gated on approved? for exactly the reason the previous implementation was:
    # a rejected or expired decision also runs a branch in the source — every
    # implementation dispatches its rejection arm — so it reports
    # DISPATCH_EXECUTED just as an approval does. But "the reject branch ran" is
    # not an execution outcome, and stamping "succeeded" on a rejected request
    # would trade the false success this change removes for a new one pointing
    # the other way. Rejected/expired keep the log-only behavior, leaving
    # execution_status nil — the defined state for "nothing executed".
    #
    # A reported no-op, or any reply outside the vocabulary (a source written
    # before this contract, a test double returning something else), also leaves
    # it nil. See DISPATCH_EXECUTED / DISPATCH_NOOP for why the source reports
    # instead of the caller inferring.
    def declare_dispatch_outcome!(outcome)
      return unless approved?
      return unless outcome == DISPATCH_EXECUTED

      declare_execution_outcome!("succeeded")
    end

    # Direct column write: this runs inside the status-flip's own after_update,
    # so re-entering the callback chain (or validations) via update! is the one
    # thing it must not do. Never raises — the enclosing rescue's contract is
    # that a declaration problem cannot take down the decision itself.
    def declare_execution_outcome!(outcome, error: nil)
      detail = error ? "#{error.class}: #{error.message}" : nil
      update_columns(execution_status: outcome, execution_error: detail,
                     updated_at: Time.current)
    rescue StandardError => e
      Rails.logger.error("[ApprovalRequest##{id}] declare_execution_outcome! failed: #{e.message}")
    end

    def declare_execution_failure!(error)
      declare_execution_outcome!("failed", error: error)
      # Recorder swallows its own errors, so a broken event sink cannot mask
      # the column declaration above or raise out of the callback.
      ::Ai::Introspection::ExecutionEventRecorder.record(
        source: self,
        event_type: "approval_execution",
        status: "failed",
        error: error,
        metadata: {
          operation_source_type: source_type,
          operation_source_id: source_id,
          action_category: request_data&.dig("action_category")
        }.compact
      )
    end

    def fan_out_step_notifications
      return unless pending?
      return unless defined?(::Ai::ApprovalRequestNotifier)

      ::Ai::ApprovalRequestNotifier.notify_current_step!(self)
    rescue StandardError => e
      Rails.logger.error("[ApprovalRequest##{id}] fan_out_step_notifications failed: #{e.message}")
    end

    def process_decision(decision)
      step_info = step_statuses[current_step]

      case decision
      when "approved"
        step_info["current_approvals"] += 1
        step_info["status"] = "approved" if step_info["current_approvals"] >= step_info["required_approvals"]

        if step_info["status"] == "approved"
          if current_step >= step_statuses.length - 1
            approve!
          else
            advance_to_next_step!
          end
        end
      when "rejected"
        step_info["status"] = "rejected"
        reject!
      when "delegated"
        # Delegation logic - could reassign to another approver
        step_info["status"] = "delegated"
      end

      update!(step_statuses: step_statuses)
    end

    def advance_to_next_step!
      update!(current_step: current_step + 1)
    end

    def escalate!
      # Could notify higher-level approvers or auto-approve
      update!(status: "expired")
    end
  end
end
