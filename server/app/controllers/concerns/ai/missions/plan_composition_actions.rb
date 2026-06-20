# frozen_string_literal: true

module Ai
  module Missions
    module PlanCompositionActions
      extend ActiveSupport::Concern

      # POST /api/v1/ai/missions/:id/compose_plan
      #
      # Infrastructure missions: returns the rich provisioning plan
      # (cost / topology / risk) sourced from PlanComposerService. Reuses
      # the cached plan when one already exists for the mission so the
      # deep-link page (`/app/system/provision?mission_id=…`) shows the
      # same data the chat already presented, no extra LLM cost.
      #
      # Other mission types: falls through to the legacy
      # SkillCompositionService task graph.
      def compose_plan
        mission = find_mission!
        return unless mission

        if mission.mission_type.to_s == "infrastructure"
          return compose_provisioning_plan(mission)
        end

        compose_skill_plan(mission)
      end

      private

      def compose_provisioning_plan(mission)
        plan = existing_provisioning_plan(mission) || compose_new_provisioning_plan(mission)
        return unless plan # error already rendered by composer

        snapshot = ::Ai::Provisioning::PlanSnapshotService
                     .new(account: current_account).snapshot(plan: plan)
        render_success(plan: snapshot.merge(mission_id: mission.id))
      end

      # Look up the plan referenced by `mission.configuration["plan"]["plan_id"]`
      # — set by the chat-tool path when it composes. Avoids re-running the LLM.
      # Runs a lazy compaction pass to fold any redundant provisioning clusters
      # that pre-date the collapse fix, so operators see a clean plan even if
      # the cached version was composed before the collapse logic existed.
      def existing_provisioning_plan(mission)
        plan_id = mission.configuration&.dig("plan", "plan_id")
        return nil if plan_id.blank?
        plan = ::Ai::GoalPlan.find_by(id: plan_id)
        return nil unless plan

        ::Ai::Provisioning::PlanComposerService
          .new(account: current_account, mission: mission)
          .compact_existing_plan!(plan)
        plan.reload
      rescue StandardError => e
        Rails.logger.warn("[MissionsController] lazy plan compaction failed: #{e.class}: #{e.message}")
        plan
      end

      def compose_new_provisioning_plan(mission)
        # Hybrid routing (shared with the worker-job + concierge paths):
        # recognized provisioning scenarios -> PlanComposerService, novel/general
        # intents -> MissionComposer. Only reached when no cached plan exists.
        composer = ::Ai::Missions::ComposerRouter.new(
          account: current_account, mission: mission
        ).select
        result = composer.compose!

        if result.is_a?(Hash) && result[:clarification_needed]
          render_error(result[:message] || "Multiple providers configured — clarify before composing",
                       :unprocessable_content,
                       details: result.except(:clarification_needed))
          return nil
        end

        unless result
          # Both composers expose cap_exceeded_payload (set when the LLM cost
          # cap gates composition); surface the upgrade message when present.
          render_error(composer.cap_exceeded_payload ? "LLM cost cap exceeded" : "Plan composition returned no plan",
                       :unprocessable_content)
          return nil
        end

        result
      rescue ::Ai::Provisioning::PlanComposerService::BriefMissingError,
             ::Ai::Provisioning::PlanComposerService::AgentMissingError,
             ::Ai::Missions::MissionComposer::CompositionError => e
        render_error(e.message, :unprocessable_content)
        nil
      end

      def compose_skill_plan(mission)
        llm_client = nil
        model = nil
        if mission.configuration&.dig("reasoning", "mode") == "star"
          credential = current_account.ai_provider_credentials
                         .joins(:provider).where(ai_providers: { is_active: true })
                         .where(is_active: true).first
          if credential
            agent = current_account.ai_agents.active.first
            llm_client = agent ? ::WorkerLlmClient.new(agent_id: agent.id) : nil
            model = credential.provider.default_model
          end
        end

        service = ::Ai::Missions::SkillCompositionService.new(
          mission: mission, llm_client: llm_client, model: model
        )
        plan = service.compose!
        render_success(plan: plan)
      rescue ::Ai::Missions::SkillCompositionService::CompositionError => e
        render_error(e.message, :unprocessable_content)
      end
    end
  end
end
