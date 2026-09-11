# frozen_string_literal: true

namespace :platform do
  desc "G2-3: rewrite investigations that carry the old evidence.errors.ranking shape. " \
       "Prints the count and a sample; acts only with CONFIRM=<current count>."
  task rewrite_legacy_ranking_errors: :environment do
    outcome = Platform::Investigation::LegacyRankingErrorRewrite.operator_run(confirm: ENV["CONFIRM"])
    exit(1) if outcome.status == :mismatch
  end
end
