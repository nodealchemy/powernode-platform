# frozen_string_literal: true

module Ai
  module SelfImprovement
    class SkillMutationService
      MUTATION_STRATEGIES = %w[learning_driven failure_analysis challenge_derived peer_comparison].freeze

      def initialize(account:)
        @account = account
      end

      def mutate!(skill:, strategy:)
        return nil unless MUTATION_STRATEGIES.include?(strategy)

        case strategy
        when "learning_driven"
          mutate_from_learnings(skill)
        when "failure_analysis"
          mutate_from_failures(skill)
        when "challenge_derived"
          mutate_from_challenges(skill)
        when "peer_comparison"
          mutate_from_peers(skill)
        end
      end

      # SQL success-rate over usage records. The table stores `outcome`
      # (string, see Ai::SkillUsageRecord::OUTCOMES) — there is no boolean
      # `success` column; querying one was the schema drift that kept the
      # weekly auto-evolution cron from ever completing (IMP-136447f24ceb).
      SUCCESS_RATE_SQL = "AVG(CASE WHEN ai_skill_usage_records.outcome = 'success' THEN 1.0 ELSE 0.0 END)"

      def auto_mutate_underperforming!(threshold: 0.4)
        mutated = 0
        Ai::Skill.where(account: @account, status: "active")
          .joins(:usage_records)
          .group("ai_skills.id")
          .having("#{SUCCESS_RATE_SQL} < ?", threshold)
          .each do |skill|
            result = mutate!(skill: skill, strategy: "failure_analysis")
            mutated += 1 if result
          end
        mutated
      end

      def compose_skills!(component_skill_ids:, name:, strategy: "sequential")
        components = Ai::Skill.where(id: component_skill_ids, account: @account)
        return nil if components.size < 2

        composite = Ai::Skill.create!(
          account: @account,
          name: name,
          description: "Composite skill: #{components.pluck(:name).join(' + ')}",
          category: components.first.category,
          status: "draft",
          is_composite: true,
          system_prompt: build_composite_prompt(components, strategy),
          metadata: { composition_strategy: strategy, component_ids: component_skill_ids }
        )

        components.each_with_index do |component, idx|
          Ai::SkillComposition.create!(
            composite_skill: composite,
            component_skill: component,
            execution_order: idx + 1,
            composition_type: strategy
          )
        end

        composite
      end

      private

      def mutate_from_learnings(skill)
        learnings = Ai::CompoundLearning.active
          .for_account(@account.id)
          .where("tags @> ?", [skill.category].to_json)
          .order(importance_score: :desc)
          .limit(5)

        return nil if learnings.empty?

        learning_context = learnings.map { |l| "- #{l.content.truncate(100)}" }.join("\n")
        create_variant(skill, "learning_driven", learning_context)
      end

      def mutate_from_failures(skill)
        failures = skill.usage_records.failed.order(created_at: :desc).limit(10)
        return nil if failures.empty?

        # Usage records carry no dedicated error column; writers put whatever
        # context exists into context_summary or metadata.
        failure_patterns = failures.map { |f|
          f.context_summary.presence || f.metadata["error"].presence || "unknown error"
        }.tally
        failure_context = failure_patterns.map { |err, count| "- #{err} (#{count}x)" }.join("\n")
        create_variant(skill, "failure_analysis", failure_context)
      end

      def mutate_from_challenges(skill)
        challenges = Ai::SelfChallenge.completed.for_skill(skill.id)
          .where("quality_score >= ?", 0.7)
          .order(quality_score: :desc)
          .limit(5)

        return nil if challenges.empty?

        challenge_context = challenges.map { |c| "- #{c.challenge_prompt&.truncate(100)}: score=#{c.quality_score}" }.join("\n")
        create_variant(skill, "challenge_derived", challenge_context)
      end

      def mutate_from_peers(skill)
        peers = Ai::Skill.where(account: @account, category: skill.category, status: "active")
          .where.not(id: skill.id)
          .joins(:usage_records)
          .group("ai_skills.id")
          .order(Arel.sql("#{SUCCESS_RATE_SQL} DESC"))
          .limit(3)

        return nil if peers.empty?

        peer_context = peers.map { |p| "- #{p.name}: #{p.system_prompt&.truncate(100)}" }.join("\n")
        create_variant(skill, "peer_comparison", peer_context)
      end

      def create_variant(skill, strategy, context)
        new_prompt = "#{skill.system_prompt}\n\n[MUTATION: #{strategy}]\nContext:\n#{context}"

        # A/B rollout is native to SkillVersion (is_ab_variant + ab_traffic_pct
        # + record_outcome!/effectiveness) — Ai::AbTest cannot represent a
        # skill target at all (target_type inclusion allows only
        # workflow/agent/prompt/model/provider), so the AbTest.create! this
        # method used to attempt was structurally invalid and rescue-nil'd on
        # every run. Version string convention follows
        # SkillGraph::EvolutionService (count + 1, unique per skill).
        # One active A/B variant per skill: record_outcome!/end_ab_test resolve
        # THE variant via .ab_variants.first, so retire any prior variant's
        # flag + traffic slice first (mirrors EvolutionService#start_ab_test).
        skill.versions.ab_variants.update_all(is_ab_variant: false, ab_traffic_pct: nil)

        Ai::SkillVersion.create!(
          account: @account,
          ai_skill: skill,
          version: (skill.versions.count + 1).to_s,
          change_type: "ab_test",
          change_reason: "Auto-mutation (#{strategy})",
          system_prompt: new_prompt.truncate(4000),
          is_active: false,
          is_ab_variant: true,
          ab_traffic_pct: 20.0,
          metadata: { mutation_strategy: strategy }
        )
      end

      def build_composite_prompt(components, strategy)
        parts = components.map.with_index do |c, i|
          "Step #{i + 1} (#{c.name}): #{c.system_prompt&.truncate(200)}"
        end

        "This is a composite skill that combines #{components.size} capabilities.\n" \
        "Execution strategy: #{strategy}\n\n" \
        "Components:\n#{parts.join("\n")}"
      end
    end
  end
end
