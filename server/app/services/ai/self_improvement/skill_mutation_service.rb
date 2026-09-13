# frozen_string_literal: true

module Ai
  module SelfImprovement
    class SkillMutationService
      # SCHEDULED auto-evolution is OFF unless an operator turns it on (D6).
      #
      # `AiSkillAutoEvolutionJob` runs WEEKLY, for EVERY active account, and
      # until now carried no feature flag and no approval gate — the
      # `dev.skill_refine` gate lives on the MCP verb, not on the internal
      # endpoint the cron posts to. It creates A/B prompt variants at 20%
      # traffic that Ai::SkillGraph::EvolutionService genuinely serves. The
      # audit's reading: harmless only by accident, because what it writes is
      # currently inert — and it stops being harmless the moment increment D5
      # makes an activated version's prompt actually reach a runtime reader.
      #
      # THE GATE IS ON THE ENDPOINT, NOT HERE, and the distinction is
      # load-bearing: `#auto_mutate_underperforming!` is shared by the cron and
      # by the `auto_evolve_skill` MCP verb, which carries its own approval gate
      # (`dev.skill_refine`) and must keep working. Gating the service would
      # silently disarm that verb too. The constant lives on this class because
      # the key belongs next to the behaviour it names — the same convention
      # Devops::IntegrationInstance and Ai::Autonomy::ClosureDriverService
      # follow — and the endpoint reads it.
      AUTO_EVOLUTION_SETTING = "ai.skill_auto_evolution_enabled"

      # STRICT, and fail-closed (D6 review F4). Only these four values turn the
      # cron on; everything else — a missing row, nil, "false", and every
      # spelling of no — leaves it off. A generic boolean cast was wrong here:
      # ActiveModel::Type::Boolean reads "no", "n" and "disabled" as TRUE, and
      # a row reaches this method as a raw string whenever its setting_type is
      # not boolean, which the admin update endpoint lets an operator change.
      # An operator typing "no" must not switch on a weekly sweep over every
      # account. SiteSetting.get's own boolean branch has a third truth table
      # again, so this one is stated here rather than borrowed.
      AUTO_EVOLUTION_ON_VALUES = [ true, "true", "1", 1 ].freeze

      def self.auto_evolution_enabled?
        AUTO_EVOLUTION_ON_VALUES.include?(::SiteSetting.get(AUTO_EVOLUTION_SETTING))
      end

      # `challenge_derived` was removed with the self-challenge subsystem (D6):
      # it read Ai::SelfChallenge rows, and that table is gone. A caller passing
      # it now falls through #mutate!'s membership guard and gets nil, which is
      # the same answer the strategy itself returned whenever no completed
      # challenge existed — i.e. always, since nothing ever completed one.
      MUTATION_STRATEGIES = %w[learning_driven failure_analysis peer_comparison].freeze

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
        #
        # D5: the A/B is STARTED by EvolutionService#start_ab_test, not by
        # writing the flag here. This method used to set `ab_traffic_pct: 20.0`
        # directly — a percent, where every reader treats the column as a
        # fraction (`rand < ab_traffic_pct`), so the variant absorbed 100% of
        # recorded outcomes. start_ab_test owns the default share, the clamp
        # and the one-variant-per-skill retirement, so routing through it is
        # the whole fix rather than a second copy of the rule.
        #
        # A refusal rolls the version back: a variant row whose A/B never
        # started is an inert orphan that still consumes a version number.
        Ai::SkillVersion.transaction do
          version = Ai::SkillVersion.create!(
            account: @account,
            ai_skill: skill,
            version: (skill.versions.count + 1).to_s,
            change_type: "ab_test",
            change_reason: "Auto-mutation (#{strategy})",
            system_prompt: new_prompt.truncate(4000),
            is_active: false,
            is_ab_variant: false,
            metadata: { mutation_strategy: strategy }
          )

          started = Ai::SkillGraph::EvolutionService.new(@account)
            .start_ab_test(skill_id: skill.id, variant_version_id: version.id)
          if started[:error]
            Rails.logger.error("[SkillMutation] A/B start refused for skill #{skill.id}: #{started[:error]}")
            raise ActiveRecord::Rollback
          end

          version.reload
        end
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
