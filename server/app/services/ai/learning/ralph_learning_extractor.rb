# frozen_string_literal: true

module Ai
  module Learning
    # Tier-2(c): promotes ralph-loop iteration learnings (the JSON entries that
    # accumulate in ralph_loop.learnings) into durable CompoundLearning records so
    # effective_importance / decay can measure them over time. This wires up the
    # gap recon identified: loop learnings were appended to JSON but never reached
    # the compounding-learning store.
    #
    # Reuses CompoundLearningService#store_learning for embedding generation and
    # near-duplicate dedup (so re-harvesting is idempotent). Seeds a low initial
    # importance so learnings must earn their ranking through reuse outcomes, and
    # scopes each to the loop's git_repository when resolvable (Tier-2(d) FK).
    class RalphLearningExtractor
      INITIAL_IMPORTANCE = 0.3
      INITIAL_CONFIDENCE = 0.5

      def initialize(account:)
        @account = account
        @service = Ai::Learning::CompoundLearningService.new(account: account)
      end

      # Harvest all of a loop's accumulated learnings. Idempotent. Returns the
      # number of new CompoundLearning records created.
      def extract(ralph_loop)
        repo_id = repository_id_for(ralph_loop)
        Array(ralph_loop.learnings).sum do |entry|
          store(entry_text(entry), repo_id: repo_id) ? 1 : 0
        end
      rescue StandardError => e
        Rails.logger.warn("[RalphLearningExtractor] extract failed for loop #{ralph_loop&.id}: #{e.message}")
        0
      end

      # Harvest a single learning string (per-iteration callers). Returns true
      # when a new record was created.
      def extract_learning(ralph_loop, text)
        store(text, repo_id: repository_id_for(ralph_loop))
      rescue StandardError => e
        Rails.logger.warn("[RalphLearningExtractor] extract_learning failed: #{e.message}")
        false
      end

      private

      def store(text, repo_id:)
        return false if text.blank?

        # store_learning takes a positional Hash (not kwargs) — pass it explicitly.
        @service.store_learning({
          content: text,
          category: "discovery",
          importance: INITIAL_IMPORTANCE,
          confidence: INITIAL_CONFIDENCE,
          extraction_method: "ralph_loop",
          git_repository_id: repo_id,
          tags: ["ralph_loop"]
        })
      end

      def entry_text(entry)
        entry.is_a?(Hash) ? entry["text"] : entry.to_s
      end

      # Resolve the loop's repository_url to a GitRepository in this account.
      # Returns nil when there's no URL or no match (learning stays account-global).
      def repository_id_for(ralph_loop)
        url = ralph_loop.respond_to?(:repository_url) ? ralph_loop.repository_url : nil
        return nil if url.blank?

        Devops::GitRepository.where(account_id: @account.id)
                             .where("clone_url = :u OR web_url = :u OR ssh_url = :u OR full_name = :u", u: url)
                             .first&.id
      end
    end
  end
end
