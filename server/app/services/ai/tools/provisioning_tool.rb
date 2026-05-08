# frozen_string_literal: true

module Ai
  module Tools
    # Golden Eclipse M0 — MCP-facing surface for the AI-driven provisioning
    # conversation.
    #
    # Wraps the three provisioning services
    # (Ai::Provisioning::IntentCaptureService, PlanComposerService,
    # SkillCompositionRunner) plus the mission/plan persistence layer, so
    # operators (and the Concierge tool bridge) can drive the full
    # capture → compose → approve → execute → status → adapt cycle through
    # one tool surface.
    #
    # Action shapes match the M0 plan:
    #   platform_provisioning_capture_brief  — NL + optional mission_id → brief + missing fields
    #   platform_provisioning_compose_plan   — mission_id → plan_id + DAG (cost/topology/risk nil for M0)
    #   platform_provisioning_approve_plan   — plan_id + decision → mission status transition
    #   platform_provisioning_execute        — mission_id → runner_id + step_count
    #   platform_provisioning_status         — mission_id → phase + step lists
    #   platform_provisioning_adapt          — M0 stub returning { todo: "M2", adaptation_plan: nil }
    #
    # Adapt is intentionally inert in M0; the actual adaptation engine ships
    # with the ProjectSloSensor reconciler in M2.
    class ProvisioningTool < BaseTool
      MISSION_TEMPLATE_NAME = "system_provisioning"
      VALID_DECISIONS = %w[approved rejected modified].freeze

      def self.definition
        {
          name: "provisioning",
          description: "AI-driven natural-language provisioning conversation: capture brief, compose plan, approve, execute, monitor, adapt",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" }
          }
        }
      end

      def self.action_definitions
        {
          "platform_provisioning_capture_brief" => {
            description: "Translate a natural-language utterance into a structured Project Brief. " \
                         "When mission_id is omitted, creates a new infrastructure mission bound to the " \
                         "system_provisioning template. When mission_id is provided, treats the utterance as " \
                         "a clarification and merges fields onto the existing brief. Returns the brief plus " \
                         "the list of fields still missing for plan composition.",
            parameters: {
              mission_id: { type: "string", required: false,
                            description: "Existing infrastructure mission ID — omit to create a new one" },
              natural_language: { type: "string", required: true,
                                  description: "Operator's natural-language description of what they want to provision" },
              prior_brief: { type: "object", required: false,
                             description: "Optional existing brief to merge new fields onto " \
                                          "(auto-loaded from mission.configuration['brief'] when mission_id is given)" }
            }
          },
          "platform_provisioning_compose_plan" => {
            description: "Run the LLM goal-decomposition kernel against the mission's brief and produce a " \
                         "persisted Ai::GoalPlan whose steps are rewritten into provisioning_skill shape. " \
                         "Returns the DAG plus M1 enrichments: cost_estimate (CostEstimatorService), " \
                         "topology_preview (TopologyRendererService), and risk (RiskScorerService).",
            parameters: {
              mission_id: { type: "string", required: true, description: "Infrastructure mission ID" }
            }
          },
          "platform_provisioning_approve_plan" => {
            description: "Operator decision on a composed plan. decision='approved' advances the mission past " \
                         "the review_plan gate; 'rejected' sends it back to compose_plan via rejection_mappings; " \
                         "'modified' applies inline edits to the plan steps before approving. The optional " \
                         "approval_request_id field in the response is reserved for M1 when this routes through " \
                         "the formal approval pipeline.",
            parameters: {
              plan_id: { type: "string", required: true, description: "Ai::GoalPlan ID returned by compose_plan" },
              decision: { type: "string", required: true,
                          description: "One of: approved, rejected, modified" },
              modifications: { type: "object", required: false,
                               description: "Optional plan-step edits to apply when decision='modified' " \
                                            "(shape: { steps: [{ step_number: Int, skill: String }] })" }
            }
          },
          "platform_provisioning_execute" => {
            description: "Kick off the SkillCompositionRunner for the mission's most recent plan. Returns " \
                         "the runner_id, started_at, and step_count. Subsequent step progress streams via " \
                         "MissionChannel events (provisioning_run_started + provisioning_step_changed); use " \
                         "platform_provisioning_status for snapshot polling.",
            parameters: {
              mission_id: { type: "string", required: true, description: "Infrastructure mission ID" }
            }
          },
          "platform_provisioning_status" => {
            description: "Snapshot of provisioning progress: mission phase, currently-executing step number, " \
                         "and step-number lists by status (completed, pending, failed). For live streaming " \
                         "subscribe to MissionChannel rather than polling this.",
            parameters: {
              mission_id: { type: "string", required: true, description: "Infrastructure mission ID" }
            }
          },
          "platform_provisioning_adapt" => {
            description: "M0 stub — adaptation engine ships with the ProjectSloSensor reconciler in M2. " \
                         "Returns { todo: 'M2', adaptation_plan: nil } today; will accept a proposed_change " \
                         "(scale_horizontal, cost_control, schema_change, etc.) and return a remediation plan " \
                         "in M2.",
            parameters: {
              mission_id: { type: "string", required: true, description: "Infrastructure mission ID" },
              proposed_change: { type: "object", required: false,
                                 description: "Optional shape of the adaptation; ignored in M0" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "platform_provisioning_capture_brief"  then capture_brief(params)
        when "platform_provisioning_compose_plan"   then compose_plan(params)
        when "platform_provisioning_approve_plan"   then approve_plan(params)
        when "platform_provisioning_execute"        then execute_plan(params)
        when "platform_provisioning_status"         then status_snapshot(params)
        when "platform_provisioning_adapt"          then adapt(params)
        else
          error_result("Unknown action: #{params[:action]}")
        end
      rescue ActiveRecord::RecordNotFound => e
        error_result(e.message)
      rescue ArgumentError => e
        error_result(e.message)
      end

      private

      # ===== Action handlers =====

      def capture_brief(params)
        nl = params[:natural_language].to_s
        return error_result("natural_language is required") if nl.strip.empty?

        mission, prior_brief =
          if params[:mission_id].present?
            m = find_mission!(params[:mission_id])
            cfg_brief = m.configuration.is_a?(Hash) ? m.configuration["brief"] : nil
            [m, params[:prior_brief].presence || cfg_brief]
          else
            [create_infrastructure_mission!(name_hint: nl), params[:prior_brief]]
          end

        service = build_intent_service(mission)
        result =
          if prior_brief.is_a?(Hash) && prior_brief.any?
            service.refine(brief: prior_brief, clarification: nl)
          else
            service.capture(natural_language: nl, prior_brief: prior_brief)
          end

        persist_brief!(mission, result[:brief])

        # If the brief is now complete, advance the mission off the
        # capture_intent phase so the chat surface and direct MCP callers
        # see the same phase progression as the worker-job-driven flow.
        advance_to_compose_plan!(mission) if Array(result[:missing_fields]).empty?

        success_result(
          mission_id: mission.id,
          brief: result[:brief],
          missing_fields: result[:missing_fields]
        )
      end

      def compose_plan(params)
        mission = find_mission!(params[:mission_id])
        result = ::Ai::Provisioning::PlanComposerService.new(account: account, mission: mission).compose!

        # M2 BYOC routing — when the account has multiple providers configured
        # AND the brief lacks an unambiguous preferred_provider, PlanComposer
        # short-circuits and returns a clarification payload. Forward it to the
        # chat surface (Slice B renders it as provider chips); the mission
        # stays in compose_plan so the next capture_brief / compose_plan round
        # can apply the operator's selection.
        if result.is_a?(Hash) && result[:clarification_needed]
          return success_result(
            mission_id: mission.id,
            clarification_needed: true,
            message: result[:message],
            available_providers: result[:available_providers]
          )
        end

        plan = result
        return error_result("Plan composition returned no plan — verify the brief is complete") unless plan

        # Plan exists, mission can sit at review_plan awaiting operator decision.
        advance_to_review_plan!(mission)

        success_result(
          plan_id: plan.id,
          dag: serialize_dag(plan),
          cost_estimate: build_cost_estimate(plan),
          topology_preview: build_topology_preview(plan),
          risk: build_risk(plan)
        )
      rescue ::Ai::Provisioning::PlanComposerService::BriefMissingError,
             ::Ai::Provisioning::PlanComposerService::AgentMissingError => e
        error_result(e.message)
      end

      # ===== Plan-review enrichments (M1) =====

      def build_cost_estimate(plan)
        ::Ai::Provisioning::CostEstimatorService.new(account: account).estimate(plan: plan)
      rescue StandardError => e
        Rails.logger.warn("[ProvisioningTool] cost estimate failed: #{e.class}: #{e.message}")
        { monthly_usd: 0.0, one_time_usd: 0.0, by_resource: [], confidence: "low" }
      end

      def build_topology_preview(plan)
        ::Ai::Provisioning::TopologyRendererService.new(account: account, plan: plan).render
      rescue StandardError => e
        Rails.logger.warn("[ProvisioningTool] topology render failed: #{e.class}: #{e.message}")
        { nodes: [], edges: [], regions: [], estimated_resources: [] }
      end

      def build_risk(plan)
        ::Ai::Provisioning::RiskScorerService.new(account: account).score(plan: plan)
      rescue StandardError => e
        Rails.logger.warn("[ProvisioningTool] risk scoring failed: #{e.class}: #{e.message}")
        { score: 0, severity: "low", factors: [] }
      end

      def approve_plan(params)
        plan = find_plan!(params[:plan_id])
        decision = params[:decision].to_s
        unless VALID_DECISIONS.include?(decision)
          return error_result("decision must be one of: #{VALID_DECISIONS.join(', ')}")
        end

        mission = mission_for_plan(plan)
        return error_result("Plan #{plan.id} is not bound to an infrastructure mission") unless mission

        case decision
        when "approved"
          advance_past_review_gate!(mission)
        when "rejected"
          send_back_to_compose!(mission)
          plan.reject!(reason: "Operator rejected at review_plan gate") if plan.respond_to?(:reject!)
        when "modified"
          apply_modifications!(plan, params[:modifications])
          advance_past_review_gate!(mission)
        end

        success_result(
          plan_id: plan.id,
          plan: serialize_plan(plan.reload),
          approval_request_id: nil,
          mission_status: mission.reload.status
        )
      end

      def execute_plan(params)
        mission = find_mission!(params[:mission_id])
        plan = latest_plan_for(mission)
        return error_result("No plan exists for mission #{mission.id} — run compose_plan first") unless plan

        # M1 Self-Serve Hardening — gate execution on the active subscription's
        # plan limits. On denial, return a structured `requires_upgrade: true`
        # payload that the frontend (UpgradeRequiredCard, Slice D) consumes
        # rather than running the SkillCompositionRunner.
        if defined?(::Billing::ProvisioningQuotaGuard)
          allow, reason = ::Billing::ProvisioningQuotaGuard.allow?(account: account, mission: mission)
          unless allow
            payload = ::Billing::ProvisioningQuotaGuard.upgrade_payload(reason: reason, account: account)
            return success_result(payload.merge(mission_id: mission.id))
          end
        end

        runner = ::Ai::Provisioning::SkillCompositionRunner.new(
          account: account, mission: mission, plan: plan
        )
        result = runner.execute!

        success_result(
          runner_id: result[:runner_id],
          started_at: result[:started_at].respond_to?(:iso8601) ? result[:started_at].iso8601 : result[:started_at],
          step_count: result[:step_count]
        )
      end

      def status_snapshot(params)
        mission = find_mission!(params[:mission_id])
        plan = latest_plan_for(mission)
        steps = plan ? plan.steps.reload.to_a : []

        completed = steps.select { |s| step_status_str(s) == "completed" }.map(&:step_number)
        pending   = steps.select { |s| step_status_str(s) == "pending" }.map(&:step_number)
        failed    = steps.select { |s| step_status_str(s) == "failed" }.map(&:step_number)
        current   = steps.find  { |s| step_status_str(s) == "executing" }&.step_number

        success_result(
          phase: mission.current_phase,
          current_step: current,
          completed: completed,
          pending: pending,
          failed: failed
        )
      end

      def adapt(_params)
        success_result(todo: "M2", adaptation_plan: nil)
      end

      # ===== Mission / plan lookups =====

      def find_mission!(id)
        return raise(ArgumentError, "mission_id is required") if id.blank?
        mission = account.ai_missions.find_by(id: id)
        raise ActiveRecord::RecordNotFound, "Mission not found: #{id}" unless mission
        unless mission.mission_type == "infrastructure"
          raise ArgumentError, "Mission #{id} is not an infrastructure mission (got #{mission.mission_type})"
        end
        mission
      end

      def find_plan!(id)
        return raise(ArgumentError, "plan_id is required") if id.blank?
        plan = ::Ai::GoalPlan.find_by(id: id, account_id: account.id)
        raise ActiveRecord::RecordNotFound, "Plan not found: #{id}" unless plan
        plan
      end

      # The provisioning goal stamps `metadata.provisioning_mission_id` in
      # PlanComposerService#find_or_create_goal!; we walk back through the
      # goal to recover the binding.
      def mission_for_plan(plan)
        meta = plan.goal&.metadata || {}
        mission_id = meta.is_a?(Hash) ? meta["provisioning_mission_id"] : nil
        return nil unless mission_id
        account.ai_missions.find_by(id: mission_id)
      end

      def latest_plan_for(mission)
        goal_ids = ::Ai::AgentGoal
          .where(account_id: account.id)
          .where("metadata @> ?", { "provisioning_mission_id" => mission.id }.to_json)
          .pluck(:id)
        return nil if goal_ids.empty?
        ::Ai::GoalPlan.where(goal_id: goal_ids).order(created_at: :desc).first
      end

      # ===== Mission creation =====

      def create_infrastructure_mission!(name_hint:)
        unless user
          raise ArgumentError,
                "user context is required to create an infrastructure mission " \
                "(BaseTool was constructed without :user)"
        end

        template = ::Ai::MissionTemplate.find_by(
          name: MISSION_TEMPLATE_NAME, template_type: "system"
        )
        unless template
          raise ArgumentError,
                "Mission template '#{MISSION_TEMPLATE_NAME}' not seeded — " \
                "run extensions/system/server/db/seeds/system_provisioning_mission_template.rb"
        end

        account.ai_missions.create!(
          name: derive_name(name_hint),
          mission_type: "infrastructure",
          status: "draft",
          mission_template: template,
          current_phase: "capture_intent",
          objective: name_hint.to_s.truncate(2000),
          created_by: user,
          configuration: { "brief" => {} }
        )
      end

      def derive_name(text)
        snippet = text.to_s.strip.tr("\n\r", " ").squeeze(" ")
        snippet = snippet.length > 80 ? "#{snippet[0, 77]}..." : snippet
        snippet.presence || "Provisioning request #{Time.current.iso8601}"
      end

      # ===== Service builders =====

      def build_intent_service(mission)
        ::Ai::Provisioning::IntentCaptureService.new(
          account: account,
          user: user,
          conversation: mission.conversation
        )
      end

      def persist_brief!(mission, brief)
        config = mission.configuration.is_a?(Hash) ? mission.configuration.deep_dup : {}
        config["brief"] = brief
        mission.update!(configuration: config)
      end

      # ===== Phase transitions =====
      #
      # The MCP-direct flow and the worker-job-driven flow both write the
      # same data (brief, plan, approval) but only the worker-job flow used
      # to advance the mission's `current_phase`. These helpers close that
      # gap so MCP callers see the same phase progression as chat-surface
      # callers.

      def advance_to_compose_plan!(mission)
        return unless mission.current_phase == "capture_intent"
        mission.update!(current_phase: "compose_plan")
      end

      def advance_to_review_plan!(mission)
        return unless %w[capture_intent compose_plan].include?(mission.current_phase)
        mission.update!(current_phase: "review_plan")
      end

      def advance_past_review_gate!(mission)
        return unless mission.current_phase == "review_plan"
        mission.update!(current_phase: "execute")
      end

      def send_back_to_compose!(mission)
        return unless mission.current_phase == "review_plan"
        mission.update!(current_phase: "compose_plan")
      end

      # ===== Plan modifications (decision='modified') =====

      def apply_modifications!(plan, modifications)
        return unless modifications.is_a?(Hash)
        edits = modifications["steps"] || modifications[:steps]
        return unless edits.is_a?(Array)

        edits.each do |edit|
          edit = edit.deep_stringify_keys if edit.respond_to?(:deep_stringify_keys)
          next unless edit.is_a?(Hash)

          step_number = (edit["step_number"] || edit["step"]).to_i
          step = plan.steps.find_by(step_number: step_number)
          next unless step

          new_skill = edit["skill"]
          if new_skill && ::Ai::Provisioning::PlanComposerService::ALLOWED_EXECUTORS.include?(new_skill.to_s)
            cfg = step.execution_config.is_a?(Hash) ? step.execution_config.deep_dup : {}
            cfg["skill"] = new_skill
            step.update!(execution_config: cfg)
          end
        end
      end

      # ===== Serialization =====

      def serialize_dag(plan)
        steps = plan.steps.reload.to_a.sort_by { |s| s.step_number.to_i }
        {
          plan_id: plan.id,
          step_count: steps.size,
          steps: steps.map do |s|
            cfg = s.execution_config.is_a?(Hash) ? s.execution_config : {}
            {
              step_number: s.step_number,
              skill: cfg["skill"] || cfg[:skill],
              dependencies: Array(s.dependencies).map(&:to_i),
              on_failure: cfg["on_failure"] || cfg[:on_failure]
            }
          end
        }
      end

      def serialize_plan(plan)
        {
          id: plan.id,
          status: plan.respond_to?(:status) ? plan.status : nil,
          step_count: plan.steps.reload.size
        }
      end

      def step_status_str(step)
        step.respond_to?(:status) ? step.status.to_s : "pending"
      end
    end
  end
end
