# frozen_string_literal: true

module Ai
  module Learning
    # PROMOTE step of learning feed-forward (inc7): turns a durable rule earned via a
    # loop/operator CompoundLearning into a guidance-* tagged SharedKnowledge entry so
    # it is retrievable via `search_knowledge tag:guidance-*` and the dev_next_task
    # digest — the same recall path model-agnostic executors already use.
    #
    # The trigger is EXPLICIT: the loop or operator calls #promote. Nothing auto-promotes
    # (raw discoveries must earn their ranking via reuse first). Promotion REUSES the
    # key-anchored upsert machinery of Ai::Guidance::GuidanceKnowledgeSeeder
    # (upsert-by guidance_key + the gate #9 private-extension refusal), so re-promoting
    # the same slug UPDATES the entry in place rather than duplicating it.
    class GuidancePromotionService
      Result = Struct.new(:entry, :outcome, :learning, keyword_init: true) do
        def promoted?
          %i[created updated].include?(outcome)
        end

        def refused?
          outcome == :refused
        end
      end

      def initialize(account:, repository: "powernode-platform", private_names: nil)
        @account = account
        @seeder = Ai::Guidance::GuidanceKnowledgeSeeder.new(
          account: account, repository: repository, private_names: private_names
        )
      end

      # Promote either an existing CompoundLearning or ad-hoc content into a guidance
      # knowledge entry. `slug` is the stable idempotency anchor (guidance:<slug>).
      # Explicit `title`/`content` win over the learning's; `tags` are added on top of
      # the canonical guidance tags. Marks the source learning promoted_at on success.
      def promote(slug:, content: nil, title: nil, learning: nil, tags: [])
        slug = slug.to_s.strip
        content = (content.presence || learning&.content).to_s
        return Result.new(outcome: :skipped, learning: learning) if slug.blank? || content.blank?

        key = "guidance:#{slug}"
        provenance = { "source_type" => "promotion" }
        provenance["source_learning_id"] = learning.id if learning&.id

        outcome = @seeder.upsert_guidance(
          key: key,
          slug: slug,
          title: (title.presence || learning&.title.presence || slug.tr("-", " ")),
          content: content,
          provenance: provenance,
          extra_tags: Array(tags),
          source_type: "promotion"
        )

        learning&.update!(promoted_at: Time.current) if %i[created updated].include?(outcome)

        Result.new(entry: guidance_entry(key), outcome: outcome, learning: learning)
      rescue StandardError => e
        Rails.logger.warn("[GuidancePromotionService] promote failed for '#{slug}': #{e.class}: #{e.message}")
        Result.new(outcome: :error, learning: learning)
      end

      private

      def guidance_entry(key)
        Ai::SharedKnowledge
          .where(account: @account)
          .where("provenance->>'guidance_key' = ?", key)
          .first
      end
    end
  end
end
