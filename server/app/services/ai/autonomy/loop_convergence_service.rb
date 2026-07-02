# frozen_string_literal: true

module Ai
  module Autonomy
    # Loop convergence metric: the recurrence rate of already-learned bug classes
    # among discovery-surfaced improvement offers per window — makes learning
    # compounding measurable. A class "recurs" when discovery surfaces an offer
    # whose class tag was already present in prior learnings (inc7 seam: loop
    # learnings carry class:* tags; class-sweep fingerprints embed the tag as
    # `<class_tag>|<file>|<detail>`). A falling recurrence_rate over time means
    # learnings are actually preventing re-discovery of the same classes.
    #
    # Lean by design: two queries + in-memory classification, no new tables.
    # Surfaced through the existing loop-statistics seam
    # (RalphLoopTool#get_statistics → platform_get_ralph_loop_statistics).
    class LoopConvergenceService
      CLASS_TAG_PREFIX = "class:"
      DEFAULT_WINDOW_DAYS = 30
      MAX_CLASSES = 20
      # Minimum class-slug length for fuzzy fingerprint matching — guards short
      # slugs from substring false-positives.
      MIN_SLUG_LENGTH = 4
      # Learnings that still count as "learned" (disproven/superseded/deprecated don't).
      LEARNED_STATUSES = %w[active verified].freeze

      def self.compute(account:, window_days: DEFAULT_WINDOW_DAYS)
        new(account: account, window_days: window_days).compute
      end

      def initialize(account:, window_days: DEFAULT_WINDOW_DAYS)
        @account = account
        @window_days = window_days.to_i.clamp(1, 365)
      end

      # => { window_days:, improvements_scanned:, surfaced_classes:, recurrent_classes:,
      #      recurrence_rate: (nil when nothing classifiable), classes: [{tag:, occurrences:, recurrent:}] }
      def compute
        offers = window_offers
        learned = learned_class_tags # { "class:slug" => earliest learning created_at }

        classes = classify(offers, learned)
        recurrent = classes.count { |_, entry| entry[:recurrent] }

        {
          window_days: @window_days,
          improvements_scanned: offers.size,
          surfaced_classes: classes.size,
          recurrent_classes: recurrent,
          recurrence_rate: classes.empty? ? nil : (recurrent.to_f / classes.size).round(3),
          classes: classes.sort_by { |_, entry| -entry[:occurrences] }
                          .first(MAX_CLASSES)
                          .map { |tag, entry| { tag: tag, occurrences: entry[:occurrences], recurrent: entry[:recurrent] } }
        }
      end

      private

      # Discovery-surfaced code-quality offers created within the window.
      def window_offers
        Ai::ImprovementRecommendation
          .where(account_id: @account.id,
                 recommendation_type: Ai::ImprovementRecommendation::CODE_QUALITY_TYPES)
          .where(created_at: @window_days.days.ago..)
          .select(:id, :evidence, :created_at)
          .to_a
      end

      # class:* tags across the account's learnings with each tag's earliest
      # created_at (so "already learned" can be compared against surfacing time).
      def learned_class_tags
        Ai::CompoundLearning
          .from("ai_compound_learnings, jsonb_array_elements_text(ai_compound_learnings.tags) AS class_tags(tag)")
          .where(account_id: @account.id, status: LEARNED_STATUSES)
          .where("class_tags.tag LIKE ?", "#{CLASS_TAG_PREFIX}%")
          .group("class_tags.tag")
          .pluck(Arel.sql("class_tags.tag"), Arel.sql("MIN(ai_compound_learnings.created_at)"))
          .to_h
      end

      # tag => { occurrences:, first_surfaced_at:, recurrent: }
      def classify(offers, learned)
        classes = {}
        offers.each do |offer|
          tag = class_tag_for(offer, learned)
          next if tag.blank?

          entry = (classes[tag] ||= { occurrences: 0, first_surfaced_at: offer.created_at })
          entry[:occurrences] += 1
          entry[:first_surfaced_at] = [entry[:first_surfaced_at], offer.created_at].min
        end

        classes.each do |tag, entry|
          learned_at = learned[tag]
          entry[:recurrent] = learned_at.present? && learned_at < entry[:first_surfaced_at]
        end
        classes
      end

      # Class of an offer: an explicit class:* fingerprint segment (class-sweep
      # convention) wins; otherwise the longest learned class whose slug is
      # embedded in the fingerprint. Nil = unclassifiable (novel/untracked).
      def class_tag_for(offer, learned)
        fingerprint = offer.evidence.is_a?(Hash) ? offer.evidence["fingerprint"].to_s : ""
        return nil if fingerprint.blank?

        explicit = fingerprint.split("|").find { |segment| segment.start_with?(CLASS_TAG_PREFIX) }
        return explicit if explicit.present?

        learned.keys
               .select { |tag| slug = tag.delete_prefix(CLASS_TAG_PREFIX); slug.length >= MIN_SLUG_LENGTH && fingerprint.include?(slug) }
               .max_by(&:length)
      end
    end
  end
end
