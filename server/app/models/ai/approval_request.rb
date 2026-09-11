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

    # Decided only by a person in their own session: from
    # Ai::ApprovalDecision::REST_SESSION (#record_decision!), and never through
    # a tool door. A human-only tool action (MCP identity plan R2: the flag
    # Ai::AutonomyGate writes; its replay runs as #confirming_approver), or a
    # request the operator's policy marks (guard b:
    # Ai::Approvals::HumanSessionPolicy).
    def requires_human_session?
      ::Ai::Approvals::HumanSessionPolicy.required?(self)
    end

    # Came through a TOOL door (MCP identity plan D1, guard a): the gate marked
    # the door it parked from (request_data call_origin), or a row written
    # before that mark names the agent that asked for it.
    def tool_door_request?
      data = request_data.is_a?(Hash) ? request_data.with_indifferent_access : {}
      data[:call_origin].present? || data[:agent_id].present?
    end

    # Whether the principal that asked for a tool-door request is the one
    # deciding it, through a door the user's ruling on guard (a) closes to it:
    # the requesting agent, whichever user it carries, through any door; the
    # requested_by user through any door but their own session (REST_SESSION),
    # so a single-user install still decides its own requests. A request parked
    # from a person's own session keeps today's rule and is never excluded.
    def requester_excluded?(approver:, origin:, agent: nil)
      return false unless tool_door_request?

      requesting_agent_id = request_data.with_indifferent_access[:agent_id]
      return true if agent && requesting_agent_id.present? && agent.id.to_s == requesting_agent_id.to_s
      return false unless approver && requested_by_id.present? && approver.id == requested_by_id

      !::Ai::ApprovalDecision.human_session_origin?(origin)
    end

    # The person whose OWN-SESSION approval completed this request: the last
    # approving decision on the LAST step, when that decision row records
    # Ai::ApprovalDecision::REST_SESSION. The proof is read off the row, never
    # inferred: a missing origin is no person. nil until the request is
    # approved, for an approval no person made on that step (a chain's
    # timeout_action), and for one recorded from any other door.
    def confirming_approver
      return nil unless approved?

      last_step = [ step_statuses.to_a.length - 1, 0 ].max
      decision = decisions.approved.where(step_number: last_step).order(:created_at, :id).last
      return nil unless decision && ::Ai::ApprovalDecision.human_session_origin?(decision.origin)

      decision.approver
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
      # One person, one decision per step. Without this a second "approved" from
      # the same user counted toward required_approvals, so one approver could
      # satisfy a two-approval step alone. It is also what makes
      # current_step_can_approve false for someone who has already decided.
      return false if decided_current_step?(user)

      approvers = step_info["approvers"] || []
      approvers.any? { |spec| approver_matches?(spec, user) }
    end

    # Why this instance's last #record_decision! refused, when the person
    # deciding can act on the reason: an approval that would complete the
    # request, from someone its source says may not complete it (L9). nil
    # otherwise. In memory only: the caller that decided holds this instance.
    attr_reader :decision_refusal

    # `origin` names the door the decision came through (Ai::ApprovalDecision
    # ORIGINS), and the decision row records it. A requires_human_session
    # request accepts a decision only from a person's own session. Every other
    # door, and a caller that names none, is refused (fail closed). `agent` is
    # the agent a tool door carries: the principal that asked for a tool-door
    # request does not decide it (#requester_excluded?). An approval that would
    # complete the request is refused, by the decider's name, when the source
    # says that person may not complete it (L9): a human-only tool call
    # replays AS them.
    def record_decision!(approver:, decision:, comments: nil, conditions: {}, origin: nil, agent: nil)
      @decision_refusal = nil
      return false unless human_session_satisfied?(origin)
      return false if requester_excluded?(approver: approver, origin: origin, agent: agent)
      return false unless can_approve?(approver)

      # THE REQUEST ROW IS LOCKED FOR THE WHOLE DECISION. Without it two
      # concurrent decisions both pass the check above and both read-modify-write
      # step_statuses: the same approver could turn both keys of a step, and two
      # different approvers could each write current_approvals = 1 and lose a
      # key. Under the lock the check is repeated against the row as it is now.
      announce = false
      result = with_lock do
        next false unless can_approve?(approver)

        # Before the row is written, so a refused decision spends nothing.
        if decision == "approved" && completes_on_approval?
          @decision_refusal = completing_decider_refusal(approver)
          next false if @decision_refusal
        end

        step_before = current_step
        next false unless insert_decision(approver, decision, comments, conditions, origin)

        recorded = process_decision(decision)
        # A decision that neither advanced the step nor resolved the request
        # (the first of two approvals, a delegation) moves no column the
        # after_update callbacks watch, so the step's other approvers, and every
        # open queue, never heard of it. Announced for this case only: a step
        # advance already fans out through the current_step callback, and a
        # resolved request has nothing left to act on.
        announce = pending? && current_step == step_before
        recorded
      end

      # After the lock's transaction has committed, so a queue that re-reads on
      # the event sees the decision it announces.
      announce_decision_within_step if announce
      result
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

    def human_session_satisfied?(origin)
      !requires_human_session? || ::Ai::ApprovalDecision.human_session_origin?(origin)
    end

    # One more approval on the current step resolves the request: it is the
    # last step, one approval short of its tally (#process_decision's rule).
    def completes_on_approval?
      step = step_statuses.to_a[current_step]
      return false unless step.is_a?(Hash) && current_step >= step_statuses.length - 1

      approvals = decisions.where(step_number: current_step, decision: "approved").count
      approvals + 1 >= step["required_approvals"].to_i
    end

    # The source's answer to "may this person's approval complete you", asked
    # the way #notify_source_of_decision asks it to act. A source that does not
    # answer has no objection.
    def completing_decider_refusal(approver)
      return nil if source_type.blank? || source_id.blank?

      klass = source_type.safe_constantize
      return nil unless klass.respond_to?(:find_by)

      source = klass.find_by(id: source_id)
      source.respond_to?(:approval_decider_refusal) ? source.approval_decider_refusal(approver) : nil
    end

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

    # The unique index (one decision per approver per step) is the database's
    # half of the guard and the lock's backstop. A violation gets the check's
    # answer, not a 500. A savepoint, so the enclosing transaction survives the
    # refused insert.
    def insert_decision(approver, decision, comments, conditions, origin)
      self.class.transaction(requires_new: true) do
        decisions.create!(
          approver: approver,
          step_number: current_step,
          decision: decision,
          comments: comments,
          conditions: conditions,
          origin: origin
        )
      end
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end

    def decided_current_step?(user)
      return false unless user

      decisions.where(step_number: current_step, approver_id: user.id).exists?
    end

    # The two halves of the lead's ruling for a decision inside a step:
    # - the "Approval needed" card, through the same step fan-out, to the step's
    #   approvers who can still act on it (everyone who already decided the
    #   step, the decider included, is left out);
    # - a content-free queue-refresh event to every viewer of the queue, the
    #   decider included, so every open queue reconciles.
    def announce_decision_within_step
      return unless defined?(::Ai::ApprovalRequestNotifier)

      decided = decisions.where(step_number: current_step).distinct.pluck(:approver_id)
      ::Ai::ApprovalRequestNotifier.notify_current_step!(self, except_user_ids: decided)
      ::Ai::ApprovalRequestNotifier.broadcast_queue_change!(self)
    rescue StandardError => e
      Rails.logger.error("[ApprovalRequest##{id}] announce_decision_within_step failed: #{e.message}")
    end

    def process_decision(decision)
      step_info = step_statuses[current_step]

      case decision
      when "approved"
        # The tally is the step's approval ROWS, never a counter carried
        # forward in step_statuses: a counter incremented on a stale copy loses
        # a concurrent approver's key. Recounted under the lock, with this
        # decision's row already in.
        step_info["current_approvals"] = decisions.where(step_number: current_step, decision: "approved").count
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
