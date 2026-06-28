# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        # Worker-cron entry point for continual campaign-proposal discovery. Iterates
        # active, non-suspended accounts and turns their standing improvement signals into
        # deduped Ai::CampaignProposal rows (the discovery half of the control plane).
        # Server-side because the worker is Sidekiq-only and reaches the server via the
        # internal mTLS API.
        class CampaignDiscoveryController < InternalBaseController
          # POST /api/v1/internal/ai/campaign_discovery/scan
          def scan
            accounts_processed = 0
            proposals_created = 0

            Account.find_each do |account|
              next unless account.active? && !account.ai_suspended? # kill-switch

              begin
                proposals = ::Ai::Discovery::CampaignProposalService.new(account: account).scan!
                proposals_created += proposals.size
                accounts_processed += 1
              rescue StandardError => e
                Rails.logger.error "[CampaignDiscovery] failed for account #{account.id}: #{e.message}"
              end
            end

            render_success(accounts_processed: accounts_processed, proposals_created: proposals_created)
          end
        end
      end
    end
  end
end
