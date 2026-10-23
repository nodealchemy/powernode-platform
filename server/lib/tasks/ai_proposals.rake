# frozen_string_literal: true

namespace :ai do
  namespace :proposals do
    desc "Ops repair: re-label agent proposals the hourly sweep recorded as withdrawn (reviewed_at nil, written " \
         "after review_deadline) as expired. DRY RUN unless APPLY=1 (exactly '1'); ACCOUNT_ID=<uuid> narrows it."
    task backfill_expired: :environment do
      Ai::AgentProposals::ExpiryBackfill.new(
        apply: ENV["APPLY"] == "1", account_id: ENV["ACCOUNT_ID"].presence
      ).run
    end
  end
end
