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

      def auto_mutate_underperforming!(threshold: 0.4)
        mutated = 0
        Ai::Skill.where(account: @account, status: "active")
          .joins(:usage_records)
          .group("ai_skills.id")
          .having("AVG(ai_skill_usage_records.success::int) < ?", threshold)
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
        failures = skill.usage_records.where(success: false).order(created_at: :desc).limit(10)
        return nil if failures.empty?

        failure_patterns = failures.map { |f| f.error_message || "unknown error" }.tally
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
          .order(Arel.sql("AVG(ai_skill_usage_records.success::int) DESC"))
          .limit(3)

        return nil if peers.empty?

        peer_context = peers.map { |p| "- #{p.name}: #{p.system_prompt&.truncate(100)}" }.join("\n")
        create_variant(skill, "peer_comparison", peer_context)
      end

      def create_variant(skill, strategy, context)
        new_prompt = "#{skill.system_prompt}\n\n[MUTATION: #{strategy}]\nContext:\n#{context}"

        version = Ai::SkillVersion.create!(
          skill: skill,
          version_number: (skill.versions.maximum(:version_number) || 0) + 1,
          system_prompt: new_prompt.truncate(4000),
          status: "testing",
          metadata: { mutation_strategy: strategy }
        )

        # Auto-create A/B test (20% traffic to variant)
        Ai::AbTest.create!(
          account: @account,
          name: "Skill mutation: #{skill.name} - #{strategy}",
          test_type: "skill_variant",
          variant_a_id: skill.id,
          variant_b_id: skill.id,
          traffic_split: 20,
          status: "active",
          metadata: { version_id: version.id, strategy: strategy }
        ) rescue nil

        version
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
