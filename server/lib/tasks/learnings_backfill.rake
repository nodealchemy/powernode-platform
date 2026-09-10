# frozen_string_literal: true

# Operator face of Ai::Learning::CompoundLearningService#backfill_embeddings.
#
# store_learning generates a learning's embedding synchronously through the
# worker's HTTP embeddings service; when that service is unavailable the row is
# still persisted with embedding: nil and is then permanently invisible to
# nearest_neighbors — dedup no-ops, cross-team promotion never sees it, and the
# semantic branch of recall matches nothing (D7). Nothing else ever repairs
# those rows. This task is the manual repair; the compound maintenance endpoint
# calls the same service method on a schedule.
#
# Reuses the existing embedding path (the service's EmbeddingService ->
# WorkerEmbeddingClient) — no second HTTP client, no host anywhere in here.
namespace :ai do
  desc "Backfill vector embeddings for active compound learnings stored without one (idempotent; LIMIT rows per account, default 200)"
  task :backfill_learning_embeddings, [ :limit ] => :environment do |_t, args|
    limit = (args[:limit].presence || 200).to_i
    unless limit.positive?
      abort("Usage: rails ai:backfill_learning_embeddings[<limit>] — limit must be a positive integer")
    end

    totals = { accounts: 0, embedded: 0, failed: 0, remaining: 0 }
    stopped_on = nil

    Account.find_each do |account|
      result = Ai::Learning::CompoundLearningService
        .new(account: account)
        .backfill_embeddings(max_per_run: limit)

      embedded = result[:embedded].to_i
      failed = result[:failed].to_i

      # Two stop conditions, both meaning "the embedding service is not
      # answering": the service method rescued an outage into success: false,
      # or every row in the batch came back without a vector. Neither writes an
      # empty vector (backfill_embeddings only persists a truthy vector), and
      # continuing would just repeat the same failure for every account.
      if result[:success] == false
        stopped_on = "account=#{account.id}: #{result[:error]}"
        break
      elsif embedded.zero? && failed.positive?
        stopped_on = "account=#{account.id}: embedding service returned no vectors for #{failed} rows"
        break
      end

      totals[:accounts] += 1
      totals[:embedded] += embedded
      totals[:failed] += failed
      totals[:remaining] += result[:remaining].to_i

      next if embedded.zero? && failed.zero?

      line = "[ai:backfill_learning_embeddings] account=#{account.id} embedded=#{embedded} failed=#{failed} remaining=#{result[:remaining].to_i}"
      Rails.logger.info(line)
      puts line
    end

    summary = "[ai:backfill_learning_embeddings] accounts=#{totals[:accounts]} embedded=#{totals[:embedded]} failed=#{totals[:failed]} remaining=#{totals[:remaining]}"
    Rails.logger.info(summary)
    puts summary

    if stopped_on
      message = "[ai:backfill_learning_embeddings] STOPPED — embedding service unavailable (#{stopped_on}). " \
                "No embeddings were written for it; re-run once the worker embedding service is reachable."
      Rails.logger.error(message)
      abort(message)
    end
  end
end
