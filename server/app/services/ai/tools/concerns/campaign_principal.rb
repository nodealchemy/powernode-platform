# frozen_string_literal: true

module Ai
  module Tools
    module Concerns
      # The principal a tool names to Ai::Campaigns::Authorization#authorize_actor!.
      # Shared by every tool door that reaches a campaign, so they cannot disagree on
      # who is asking (IMP-a658fc220367, IMP-5e2b153a3a04).
      module CampaignPrincipal
        extend ActiveSupport::Concern

        private

        # A call with a user is asked for the permission, so it names no principal. A call
        # with no user names the agent or node instance this door was built for, or the
        # declared in-process caller; anything else carries none and is refused.
        def campaign_principal
          return nil if user

          agent || node_instance || (internal? ? ::Ai::Campaigns::Authorization::INTERNAL : nil)
        end
      end
    end
  end
end
