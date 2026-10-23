# frozen_string_literal: true

module Ai
  class AgentProposal < ApplicationRecord
    self.table_name = "ai_agent_proposals"

    # agent_create: a proposed CANONICAL agent spec (payload in proposed_changes),
    # filed by claude:import_agents (Ai::ClaudeExport::AgentImportProposer) —
    # nothing creates an agent directly on that path (canonical rule).
    PROPOSAL_TYPES = %w[
      feature knowledge_update code_change architecture
      process_improvement configuration sweep_execution agent_create
    ].freeze

    # "withdrawn" is the agent's own retraction (#withdraw!) and nothing else; a deadline
    # that lapsed is "expired" (#expire!). "implemented" needs a ref (#implement!).
    STATUSES = %w[pending_review approved rejected implemented withdrawn expired].freeze
    PRIORITIES = %w[low medium high critical].freeze

    # The types a decision may be taken on from chat (a tool door). The rest are decided
    # in the app, where the card shows the full payload (Ai::AgentProposals::Decision).
    CHAT_DECIDABLE_TYPES = %w[feature code_change process_improvement architecture knowledge_update].freeze

    # Associations
    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"
    belongs_to :target_user, class_name: "User", optional: true
    belongs_to :reviewed_by, class_name: "User", optional: true
    belongs_to :conversation, class_name: "Ai::Conversation", optional: true

    # Validations
    validates :title, presence: true, length: { maximum: 255 }
    validates :proposal_type, presence: true, inclusion: { in: PROPOSAL_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :priority, presence: true, inclusion: { in: PRIORITIES }

    # JSON columns
    attribute :impact_assessment, :json, default: -> { {} }
    attribute :proposed_changes, :json, default: -> { {} }

    # Scopes
    scope :pending, -> { where(status: "pending_review") }
    scope :reviewed, -> { where(status: %w[approved rejected]) }
    scope :overdue, -> { pending.where("review_deadline < ?", Time.current) }
    scope :by_priority, -> { order(Arel.sql("CASE priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 END")) }

    # Callbacks
    before_validation :set_review_deadline, on: :create

    # A transition that the proposal's current status does not allow (approving
    # an expired or rejected proposal, implementing one that was never approved).
    class InvalidTransition < StandardError; end

    # Approval is the triage: it records the decision, HANDS THE WORK OFF by
    # proposal_type (Ai::AgentProposals::Handoff), and audits both, atomically.
    # Idempotent: a replay (a duplicate gateway cascade, a second click) creates
    # no second task and no second "approved" row; on an approved proposal whose
    # handoff was never recorded it completes the handoff.
    def approve!(user, origin:, principal: nil, via_agent: nil, mcp_session_id: nil, instruction: nil)
      admission = Ai::AgentProposals::Decision.admit!(self, user, origin: origin, principal: principal,
                                                                  via_agent: via_agent, mcp_session_id: mcp_session_id)
      source = admission.source
      context = decision_context(admission, via_agent, origin, mcp_session_id, instruction)
      with_lock do
        if status == "approved"
          next if handoff_kind.present?

          complete_handoff!(user, source: source, context: context)
        else
          require_status!("pending_review", "approve")
          update!(status: "approved", reviewed_by: user, reviewed_at: Time.current)
          complete_handoff!(user, source: source, context: context, audit_approval: true)
        end
      end
      self
    rescue Ai::AgentProposals::Handoff::Failed
      reload
      raise
    end

    def reject!(user, origin:, principal: nil, via_agent: nil, mcp_session_id: nil, instruction: nil)
      admission = Ai::AgentProposals::Decision.admit!(self, user, origin: origin, principal: principal,
                                                                  via_agent: via_agent, mcp_session_id: mcp_session_id)
      transition!("pending_review", "reject", "rejected", actor: user, source: admission.source,
                  attrs: { status: "rejected", reviewed_by: user, reviewed_at: Time.current },
                  details: decision_context(admission, via_agent, origin, mcp_session_id, instruction))
    end

    # The agent's own retraction. `by` is the user who pressed the button, when
    # there is one. Never used for a lapse: that is #expire!.
    def withdraw!(by: nil)
      transition!("pending_review", "withdraw", "withdrawn", actor: by, attrs: { status: "withdrawn" })
    end

    # The review deadline passed with nobody deciding. reviewed_at stays nil: no
    # reviewer saw it. Written by the hourly sweep (Ai::ProposalService#expire_overdue!)
    # and by a gateway request that lapsed.
    def expire!
      transition!("pending_review", "expire", "expired", actor: nil, attrs: { status: "expired" })
    end

    # Records that the work was done, with what proves it (a landed commit sha, an
    # agent id, a campaign id, a gitops ref). A reference is mandatory: "implemented"
    # without one is a claim nobody can check.
    def implement!(ref:, actor: nil)
      raise ArgumentError, "implement! requires a ref (the commit, agent or campaign that proves it)" if ref.to_s.strip.empty?

      with_lock do
        require_status!("approved", "implement")
        update!(status: "implemented", implemented_at: Time.current, implemented_ref: ref.to_s)
        Ai::AgentProposals::Audit.record!(self, "implemented", actor: actor, source: audit_source_for(actor),
                                          details: { "implemented_ref" => implemented_ref })
      end
      self
    end

    # Approval-unification cascade target. Ai::ApprovalRequest#notify_source_of_decision
    # invokes this when a gateway-routed proposal gate resolves (see
    # Ai::Approvals::Gateway / Ai::ProposalService#open_proposal_gate!). Flips
    # the proposal to match the decision; no-op unless still pending, which
    # guards against stale or duplicate cascades. A request that LAPSED makes the
    # proposal expired (nobody decided), not rejected (somebody said no).
    def on_approval_decision(request)
      return Ai::ApprovalRequest::DISPATCH_NOOP unless pending?

      last = request.decisions.order(:created_at).last
      # The agent a tool door carried when it decided (set on the request instance by
      # record_decision!), so the funnel's rule covers this door too.
      via_agent = request.respond_to?(:decision_agent) ? request.decision_agent : nil
      case request.status
      when "approved"
        # A decision no person made (a chain's timeout_action "approve" leaves no decision
        # row) never approves a proposal: it stays pending until a person decides or it lapses.
        return Ai::ApprovalRequest::DISPATCH_NOOP if last.nil? || last.origin.blank?

        Ai::AgentProposals::Decision.call(self, "approved", last.approver, origin: last.origin, via_agent: via_agent)
      when "rejected"
        if last.nil? || last.origin.blank?
          expire! # a timeout rejection is a lapse, not somebody saying no
        else
          Ai::AgentProposals::Decision.call(self, "rejected", last.approver, origin: last.origin, via_agent: via_agent)
        end
      when "expired"
        expire!
      else
        return Ai::ApprovalRequest::DISPATCH_NOOP
      end

      Ai::ApprovalRequest::DISPATCH_EXECUTED
    end

    # Acknowledgement-only handoffs start nothing; the API and UI say so.
    def acknowledged_only?
      handoff_kind == Ai::AgentProposals::Handoff::ACKNOWLEDGED
    end

    def pending?
      status == "pending_review"
    end

    def overdue?
      pending? && review_deadline.present? && review_deadline < Time.current
    end

    private

    def require_status!(expected, verb)
      return if status == expected

      raise InvalidTransition, "cannot #{verb} a #{status} proposal (only #{expected} can be #{verb}d)"
    end

    def transition!(expected, verb, transition, actor:, attrs:, details: {}, source: nil)
      with_lock do
        require_status!(expected, verb)
        update!(attrs)
        Ai::AgentProposals::Audit.record!(self, transition, actor: actor, source: source || audit_source_for(actor),
                                                            details: details)
      end
      self
    end

    # What the audit row records about HOW the decision came in: for a chat decision, the
    # user through agent X in session S quoting the instruction, and the branch that admitted
    # it; for an internal caller, the declared principal.
    def decision_context(admission, via_agent, origin, mcp_session_id, instruction)
      {
        "decided_via" => (admission.kind == :chat ? "chat" : nil), "chat_branch" => admission.branch,
        "principal" => admission.principal, "via_agent_id" => via_agent&.id, "origin" => origin.to_s.presence,
        "mcp_session_id" => mcp_session_id,
        "instruction" => instruction.presence&.to_s&.slice(0, Ai::AgentProposals::Decision::INSTRUCTION_MAX)
      }.compact
    end

    def audit_source_for(actor)
      actor ? "api" : "system"
    end

    # Runs the handoff for an approved proposal, stores it, audits it, and closes
    # the proposal at once when the handoff itself is the implementation (agent_create).
    def complete_handoff!(user, source:, context: {}, audit_approval: false)
      handoff = Ai::AgentProposals::Handoff.call(self, actor: user)
      update!(handoff_kind: handoff.kind, handoff_id: handoff.id)
      details = handoff.details
      Ai::AgentProposals::Audit.record!(self, "approved", actor: user, source: source, details: details.merge(context)) if audit_approval
      Ai::AgentProposals::Audit.record!(self, "handed_off", actor: user, source: source, details: details)
      implement!(ref: handoff.implemented_ref) if handoff.implemented_ref.present?
    end

    def set_review_deadline
      self.review_deadline ||= 72.hours.from_now
    end
  end
end
