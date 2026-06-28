# frozen_string_literal: true

module Ai
  module Land
    # Creates a CampaignLand for a completed change-set and decides whether it
    # needs explicit approval before landing. Default is to REQUIRE approval
    # (the land sits in pending_approval until an operator approves via the
    # proposal card / governance chain). An `autonomous` campaign auto-approves
    # (enqueues immediately) — mirroring the decision-authority spectrum.
    #
    # Core-pure: only touches the governance extension behind defined?() guards,
    # mirroring Ai::AutonomyGate#require_approval_or_proceed.
    class ApprovalBinding
      def self.request_land_approval(campaign:, source_branch: nil, target_branch: "develop",
                                     description: nil, requested_by: nil, priority: 0)
        new(campaign).request_land_approval(
          source_branch: source_branch, target_branch: target_branch,
          description: description, requested_by: requested_by, priority: priority
        )
      end

      def initialize(campaign)
        @campaign = campaign
      end

      def request_land_approval(source_branch: nil, target_branch: "develop",
                                description: nil, requested_by: nil, priority: 0)
        land = @campaign.campaign_lands.create!(
          account: @campaign.account,
          source_branch: source_branch || "campaign/#{@campaign.id}",
          target_branch: target_branch,
          priority: priority,
          status: "pending_approval"
        )

        if @campaign.decision_authority == "autonomous"
          land.enqueue! # auto-approve reversible land
        elsif governance_available?
          create_governance_request(land, description: description, requested_by: requested_by)
          # If the chain couldn't be created, leave it pending for the proposal card.
        end
        # else: stays pending_approval — operator approves via the proposal card.

        land
      end

      private

      def governance_available?
        return false unless defined?(::Ai::ApprovalChain) && defined?(::Ai::Autonomy::ApprovalWorkflowService)

        ::Ai::Autonomy::ApprovalWorkflowService.governance_enabled?
      rescue StandardError
        false
      end

      # Best-effort: bind a formal ApprovalRequest to the land via a chain. The
      # request's after_update calls land.on_approval_decision, which enqueues/rejects.
      def create_governance_request(land, description:, requested_by:)
        chain = ::Ai::ApprovalChain.find_or_create_default_for(@campaign.account, "campaign_land")
        return nil unless chain.respond_to?(:create_request!)

        chain.create_request!(
          source_type: "Ai::CampaignLand", source_id: land.id,
          description: description || "Land #{land.source_branch} → #{land.target_branch}",
          requested_by: requested_by
        )
      rescue StandardError => e
        Rails.logger.warn("[ApprovalBinding] governance request failed (land #{land.id}): #{e.message}")
        nil
      end
    end
  end
end
