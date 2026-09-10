# frozen_string_literal: true

module Platform
  # Reopened, not declared: `Platform::Investigation` is the ActiveRecord
  # class in app/models. Zeitwerk resolves the namespace from that file
  # before loading this child, so `class` here is a reopen and `module`
  # would be a TypeError.
  class Investigation
    # THE CONFIDENCE RULE (design §5.3), stated so it can fail.
    #
    # A hypothesis about why something broke needs a number an operator can act
    # on. The number that is easy to compute — a candidate's share of the total
    # score — is the number that lies hardest, because **a single candidate
    # always has 100% of the total**. `attribute_failure` computes exactly that
    # today and therefore reports `confidence: 1.0` for every failure with one
    # blame candidate, which is every failure where the platform looked in one
    # place. That is not a confident attribution; it is an attribution with
    # nothing to compare against.
    #
    # So share is the STARTING point, and two independent discounts sit on top:
    #
    #   1. HOW MANY INDEPENDENT EVIDENCE CLASSES support the candidate. One
    #      class agreeing with itself is one observation. Conditions, status
    #      events, module changes, remediation history and prior learnings fail
    #      in different ways, so agreement ACROSS them is worth more than
    #      volume within one.
    #   2. HOW MANY CANDIDATES were considered at all. A lone candidate means
    #      nothing was ruled out — the search may simply have been narrow — and
    #      no amount of evidence for it establishes that nothing else did it.
    #
    # ── EMPTY EVIDENCE IS `not_measured`, NEVER 0.0 ─────────────────────────
    # 0.0 says "we looked and found nothing supporting this". `not_measured`
    # says "we have no evidence at all". The first is a finding; the second is
    # a gap, and collapsing them is the same failure the verdict ladder exists
    # to prevent one level up. The state travels under the plane's own word.
    module Confidence
      MEASURED      = "measured"
      NOT_MEASURED  = ::Platform::ComponentStatus::NOT_MEASURED

      # Each additional independent class closes half the remaining gap to 1.0:
      # 1 → 0.5, 2 → 0.75, 3 → 0.875, 4 → 0.9375. Halving is a deliberate choice
      # over a linear ramp — the SECOND class is the one that turns a single
      # observation into corroboration, and every class after that adds less.
      # Nothing reaches 1.0, because a heuristic that reports certainty is
      # asking not to be checked.
      CLASS_HALVING = 0.5

      # A lone candidate: nothing was ruled out.
      SINGLE_CANDIDATE_CEILING = 0.6

      # A lone candidate supported by a single class — the weakest evidential
      # position the assembler can be in, and the one `attribute_failure`
      # currently reports as 1.0.
      SINGLE_SOURCE_CEILING = 0.35

      class << self
        # @param candidates [Array<Hash>] each `{score:, evidence_classes: [..]}`
        #   (string or symbol keys; `evidence_classes` may be any enumerable of
        #   class names)
        # @return [Hash] `{state:, value:, share:, candidates:, evidence_classes:,
        #   ceiling:}` — `value` is nil exactly when state is `not_measured`
        def for(candidates)
          list = Array(candidates).map { |candidate| normalize(candidate) }
          supported = list.reject { |candidate| candidate[:classes].empty? && candidate[:score].zero? }

          return not_measured(list.size) if supported.empty?

          top = supported.max_by { |candidate| candidate[:score] }
          score_of(top, supported)
        end

        # The confidence of ONE candidate within a set — used when the whole
        # ranked list needs a number each, not just the winner. Same rule, so a
        # runner-up cannot outrank the winner by a different formula.
        def for_each(candidates)
          list = Array(candidates).map { |candidate| normalize(candidate) }
          supported = list.reject { |candidate| candidate[:classes].empty? && candidate[:score].zero? }

          return list.map { not_measured(list.size) } if supported.empty?

          list.map do |candidate|
            supported.include?(candidate) ? score_of(candidate, supported) : not_measured(list.size)
          end
        end

        # 1 - 0.5**n, with 0 classes scoring 0. Public because the specs assert
        # the shape of the curve directly, not only its effect.
        def class_factor(class_count)
          count = class_count.to_i
          return 0.0 if count <= 0

          (1.0 - (CLASS_HALVING**count)).round(6)
        end

        private

        def score_of(candidate, supported)
          total = supported.sum { |other| other[:score] }
          share = total.positive? ? (candidate[:score] / total) : 0.0
          classes = candidate[:classes].size
          raw = share * class_factor(classes)

          ceiling = ceiling_for(supported.size, classes)
          value = ceiling ? [ raw, ceiling ].min : raw

          {
            state: MEASURED,
            value: value.round(3),
            share: share.round(3),
            candidates: supported.size,
            evidence_classes: classes,
            ceiling: ceiling
          }
        end

        def ceiling_for(candidate_count, class_count)
          return nil if candidate_count > 1
          return SINGLE_SOURCE_CEILING if class_count <= 1

          SINGLE_CANDIDATE_CEILING
        end

        def not_measured(candidate_count)
          {
            state: NOT_MEASURED,
            value: nil,
            share: nil,
            candidates: candidate_count,
            evidence_classes: 0,
            ceiling: nil
          }
        end

        # `evidence_classes` is a SET: two status events are one class, and
        # counting them twice is exactly the volume-over-corroboration mistake
        # the rule exists to avoid.
        def normalize(candidate)
          source = candidate.respond_to?(:transform_keys) ? candidate.transform_keys(&:to_sym) : {}

          {
            score: source[:score].to_f,
            classes: Array(source[:evidence_classes]).map(&:to_s).reject(&:empty?).uniq
          }
        end
      end
    end
  end
end
