# frozen_string_literal: true

module Ai
  module AgentProposals
    # The other end of a handoff: what makes an approved Ai::AgentProposal IMPLEMENTED.
    # Both entry points are idempotent and best-effort for their callers (a report that
    # fails to close a proposal must never fail the task or campaign it reports on):
    # they return the closed proposal, or nil when there was nothing to close.
    module Completion
      module_function

      # dev_complete_task reported `task` passed with `commit_sha`, and the landing check
      # says that commit is on develop (landed == true: not "unverified", not false).
      def dev_task_landed!(task, commit_sha:, account:, actor: nil)
        proposal = linked_proposal(account, task.metadata.is_a?(Hash) ? task.metadata["proposal_id"] : nil)
        return nil unless proposal&.handoff_kind == Handoff::DEV_TASK && proposal.handoff_id == task.id
        return nil if commit_sha.to_s.strip.empty?

        close(proposal, ref: commit_sha.to_s.strip, actor: actor)
      end

      # The spawned campaign finished: close the proposal whose campaign proposal spawned it.
      def campaign_completed!(campaign)
        campaign.account.ai_campaign_proposals.where(spawned_campaign_id: campaign.id).find_each do |campaign_proposal|
          proposal = linked_proposal(campaign.account, campaign_proposal.evidence.to_h["proposal_id"])
          next unless proposal&.handoff_kind == Handoff::CAMPAIGN_PROPOSAL && proposal.handoff_id == campaign_proposal.id

          close(proposal, ref: "campaign:#{campaign.id}")
        end
      end

      # The campaign proposal an approved Ai::AgentProposal was handed to was rejected: nothing
      # will run, and the agent proposal stays approved, so say so in the audit trail.
      def campaign_proposal_rejected!(campaign_proposal, user)
        proposal = linked_proposal(campaign_proposal.account, campaign_proposal.evidence.to_h["proposal_id"])
        return nil unless proposal&.handoff_kind == Handoff::CAMPAIGN_PROPOSAL && proposal.handoff_id == campaign_proposal.id

        Audit.record!(proposal, "handoff_abandoned", actor: user, source: user ? "api" : "system",
                                                     details: { "campaign_proposal_id" => campaign_proposal.id,
                                                                "reason" => campaign_proposal.rejection_reason })
      end

      def linked_proposal(account, proposal_id)
        return nil if proposal_id.blank?

        account.ai_agent_proposals.find_by(id: proposal_id)
      end

      def close(proposal, ref:, actor: nil)
        return nil unless proposal.status == "approved"

        proposal.implement!(ref: ref, actor: actor)
      rescue Ai::AgentProposal::InvalidTransition
        nil
      end
    end
  end
end
