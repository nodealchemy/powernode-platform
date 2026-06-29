# frozen_string_literal: true

module Ai
  class ProposalService
    attr_reader :account

    def initialize(account:)
      @account = account
    end

    # Create a proposal from an agent
    def create(agent:, params:, target_user: nil)
      proposal = account.ai_agent_proposals.build(
        ai_agent_id: agent.id,
        target_user: target_user || find_default_reviewer(agent),
        **params
      )

      if proposal.save
        # Notify the target user
        outreach = AgentOutreachService.new(account: account, agent: agent)
        outreach.notify_proposal(proposal: proposal)

        open_proposal_gate!(proposal)
      end

      proposal
    end

    # Batch review multiple proposals
    def batch_review(proposal_ids:, action:, reviewer:)
      proposals = account.ai_agent_proposals.where(id: proposal_ids, status: "pending_review")
      results = []

      proposals.find_each do |proposal|
        case action
        when "approve"
          proposal.approve!(reviewer)
          results << { id: proposal.id, status: "approved" }
        when "reject"
          proposal.reject!(reviewer)
          results << { id: proposal.id, status: "rejected" }
        end
      end

      results
    end

    # Auto-expire overdue proposals
    def expire_overdue!
      expired = account.ai_agent_proposals.overdue
      count = 0

      expired.find_each do |proposal|
        proposal.update!(status: "withdrawn")
        count += 1
      end

      count
    end

    private

    # Approval-unification (flag-gated): open a governance ApprovalRequest for a
    # newly-created proposal so its approve/reject decision can flow through the
    # canonical Ai::Approvals::Gateway and cascade back via
    # Ai::AgentProposal#on_approval_decision. Default OFF (governance absent or
    # flag unset) and best-effort — never breaks proposal creation.
    def open_proposal_gate!(proposal)
      return unless gateway_routing?

      Ai::Approvals::Gateway.new(account: account).request!(
        approvable: proposal,
        kind: "agent_proposal",
        requested_by: proposal.target_user,
        request_data: { proposal_type: proposal.proposal_type, title: proposal.title }
      )
    rescue StandardError => e
      Rails.logger.warn("[ProposalService] open_proposal_gate! failed for proposal #{proposal.id}: #{e.class}: #{e.message}")
    end

    def gateway_routing?
      Ai::Approvals::Gateway.governance_enabled? &&
        !!account.settings&.dig("ai", "approvals_via_gateway")
    end

    def find_default_reviewer(agent)
      # Priority: most recent user who interacted with this agent → account owner
      recent_user_id = Ai::Conversation
        .where(account_id: account.id, ai_agent_id: agent.id)
        .where.not(user_id: nil)
        .order(updated_at: :desc)
        .limit(1)
        .pluck(:user_id)
        .first

      if recent_user_id
        User.find_by(id: recent_user_id)
      else
        account.owner
      end
    end
  end
end
