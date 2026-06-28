# frozen_string_literal: true

module Ai
  module CampaignProposals
    # Spawns the Ai::Campaign for a proposal (via the CampaignDriver) and back-links it.
    # The single seam used by the REST controller, the MCP CampaignTool, and the concierge,
    # so "spawn a proposal" means the same thing everywhere. Idempotent: a proposal that is
    # already spawned returns its existing campaign rather than creating a second one.
    class SpawnService
      # A proposal may only be spawned from a reviewed-but-not-terminal state. (A rejected
      # proposal must NOT be resurrectable; a freshly proposed one must be queued/approved first.)
      SPAWNABLE_STATUSES = %w[queued approved].freeze

      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      # Returns the spawned (or already-spawned) Ai::Campaign. Takes a row lock so two
      # concurrent spawns can't each create a campaign (one wins; the other returns it).
      def spawn!(proposal)
        raise ArgumentError, "proposal belongs to another account" unless proposal.account_id == @account.id

        proposal.with_lock do
          if proposal.status == "spawned" && proposal.spawned_campaign
            return proposal.spawned_campaign
          end
          unless SPAWNABLE_STATUSES.include?(proposal.status)
            raise ArgumentError, "proposal is #{proposal.status}; only #{SPAWNABLE_STATUSES.join('/')} proposals can be spawned"
          end

          result = Ai::DevLoop::CampaignDriver.new(account: @account, user: @user).start(**proposal.to_campaign_args)
          campaign = result[:campaign]
          proposal.mark_spawned!(campaign)
          campaign
        end
      end
    end
  end
end
