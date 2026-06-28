# frozen_string_literal: true

module Ai
  module CampaignProposals
    # Spawns the Ai::Campaign for a proposal (via the CampaignDriver) and back-links it.
    # The single seam used by the REST controller, the MCP CampaignTool, and the concierge,
    # so "spawn a proposal" means the same thing everywhere. Idempotent: a proposal that is
    # already spawned returns its existing campaign rather than creating a second one.
    class SpawnService
      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      # Returns the spawned (or already-spawned) Ai::Campaign.
      def spawn!(proposal)
        raise ArgumentError, "proposal belongs to another account" unless proposal.account_id == @account.id

        if proposal.status == "spawned" && proposal.spawned_campaign
          return proposal.spawned_campaign
        end

        result = Ai::DevLoop::CampaignDriver.new(account: @account, user: @user).start(**proposal.to_campaign_args)
        campaign = result[:campaign]
        proposal.mark_spawned!(campaign)
        campaign
      end
    end
  end
end
