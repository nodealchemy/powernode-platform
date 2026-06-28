# frozen_string_literal: true

module Ai
  module Land
    # Surfaces a pending campaign land for human approval. Delivers a proactive
    # notification (deep-linking the Campaigns dashboard) carrying the action
    # metadata an inline Approve/Reject card needs. Reuses Notification (the
    # lower-level seam) so it works without an originating agent.
    class ProposalService
      MAX_APPROVERS = 5

      def self.deliver(land)
        new(land).deliver
      end

      def initialize(land)
        @land = land
        @campaign = land.campaign
      end

      def deliver
        approvers.each do |user|
          Notification.create_for_user(
            user,
            type: "campaign_land_approval",
            title: "Approve land: #{@campaign.name}",
            message: "Campaign **#{@campaign.name}** is ready to land " \
                     "`#{@land.source_branch}` → `#{@land.target_branch}`. Review and approve to merge.",
            severity: "info",
            category: "ai",
            action_url: "/app/ai/campaigns/#{@campaign.id}",
            metadata: {
              campaign_land_id: @land.id,
              campaign_id: @campaign.id,
              action_type: "approve_campaign_land",
              actions: [
                { type: "confirm", label: "Approve", action_type: "approve_campaign_land", style: "primary" },
                { type: "reject", label: "Reject", action_type: "reject_campaign_land", style: "secondary" }
              ]
            }
          )
        end
        @land
      rescue StandardError => e
        Rails.logger.warn("[Ai::Land::ProposalService] delivery failed for land #{@land.id}: #{e.message}")
        @land
      end

      private

      # Who should approve: the campaign creator, else up to N account users.
      def approvers
        [ @campaign.created_by ].compact.presence || @campaign.account.users.limit(MAX_APPROVERS).to_a
      end
    end
  end
end
