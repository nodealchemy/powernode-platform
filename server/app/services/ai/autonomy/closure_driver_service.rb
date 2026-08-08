# frozen_string_literal: true

module Ai
  module Autonomy
    # The scheduled driver that closes the core OODA loop (IMP-e041c835a40d).
    # Before this, AiObservationPipelineJob wrote observations every 15
    # minutes whose only readers were prompt-prose rendering and cleanup —
    # RalphLoopClosureService (a full observe/orient/decide/act/learn cycle)
    # had zero production call-sites. Driven by the worker's
    # ai_closure_driver cron via /api/v1/internal/ai/closure_driver/run.
    #
    # ACTIVATION IS EXPLICIT. Four independent gates, in order:
    #   1. ai.autonomy.closure_driver_enabled SiteSetting — defaults OFF, so
    #      deploying this driver changes nothing until an operator enables it.
    #   2. Account kill switch (ai_suspended?) — emergency_halt stops cycles.
    #   3. Control-plane fence via the defined? extension seam — a standby
    #      plane never drives cycles (inert in core-only assemblies and
    #      until a coordinator is armed).
    #   4. Cost backstops: DutyCycleService's per-agent daily action budget
    #      is reused, plus a hard per-tick agent cap.
    class ClosureDriverService
      ENABLED_SETTING = "ai.autonomy.closure_driver_enabled"
      AGENTS_PER_TICK = 3

      def self.enabled?
        ActiveModel::Type::Boolean.new.cast(::SiteSetting.get(ENABLED_SETTING)) || false
      end

      def initialize(account:)
        @account = account
      end

      def run
        return { enabled: false, cycles_run: 0 } unless self.class.enabled?
        return { enabled: true, halted: true, cycles_run: 0 } if @account.ai_suspended?
        return { enabled: true, standby: true, cycles_run: 0 } unless control_plane_active?

        cycles_run = 0
        cycles_failed = 0
        skipped_over_budget = 0

        eligible_agents.each do |agent|
          if DutyCycleService.daily_limit_exceeded?(agent)
            skipped_over_budget += 1
            next
          end

          begin
            RalphLoopClosureService.new(account: @account, agent: agent).execute_cycle
            cycles_run += 1
          rescue StandardError => e
            cycles_failed += 1
            Rails.logger.error(
              "[ClosureDriverService] cycle failed for agent #{agent.id}: #{e.class}: #{e.message}"
            )
          end
        end

        {
          enabled: true, cycles_run: cycles_run, cycles_failed: cycles_failed,
          skipped_over_budget: skipped_over_budget
        }
      end

      private

      # Agents worth a cycle: active agents holding at least one active goal —
      # a cycle for a goalless agent is guaranteed idle spend. Capped hard per
      # tick; the cadence provides fairness over time (ordered by the goal
      # least recently updated, so starved agents surface first).
      def eligible_agents
        @account.ai_agents
                .where(status: "active")
                .joins("INNER JOIN ai_agent_goals ON ai_agent_goals.ai_agent_id = ai_agents.id")
                .where(ai_agent_goals: { status: "active" })
                .group("ai_agents.id")
                .order(Arel.sql("MIN(ai_agent_goals.updated_at) ASC"))
                .limit(AGENTS_PER_TICK)
      end

      # Extension seam (same defined? pattern as ai/provisioning's System::
      # probes): the control-plane role lives in extensions/system. Absent
      # extension or unarmed coordinator ⇒ active (single-plane default).
      def control_plane_active?
        return true unless defined?(::System::Autonomy::ControlPlaneRole)

        ::System::Autonomy::ControlPlaneRole.active?
      end
    end
  end
end
