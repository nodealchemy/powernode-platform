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
    #   platform_provisioning_approve_plan   — plan_id + decision → mission status transition (also kicks off execution via the orchestrator)
    #   platform_provisioning_status         — mission_id → phase + step lists
    #   platform_provisioning_adapt          — mission_id + change_type → diff plan + approval routing outcome
    #
    # Note: there is intentionally NO `platform_provisioning_execute` action.
    # The approve_plan action advances the mission past `review_plan`, which
    # the orchestrator picks up and triggers AiProvisioningExecuteJob → the
    # SkillCompositionRunner. A separate execute action would race with that
    # path and double-provision (root cause of an early-M1 incident where
    # two duplicate VMs spun up because the Concierge LLM called approve and
    # then execute as separate tool calls).
    #
    # `adapt` composes but never applies: it hands the request to
    # Ai::Provisioning::AdaptationProposerService — the same service the
    # ProjectSloSensor-driven reconciler uses — which persists a diff plan and
    # routes it through Ai::Autonomy::ApprovalWorkflowService. Whether that
    # plan runs is the operator's intervention policy's decision, not this
    # tool's.
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
          "platform_provisioning_status" => {
            description: "Snapshot of provisioning progress: mission phase, currently-executing step number, " \
                         "and step-number lists by status (completed, pending, failed). For live streaming " \
                         "subscribe to MissionChannel rather than polling this.",
            parameters: {
              mission_id: { type: "string", required: true, description: "Infrastructure mission ID" }
            }
          },
          "platform_provisioning_adapt" => {
            description: "Propose an adaptation to a live infrastructure mission. Composes a diff-shaped " \
                         "Ai::GoalPlan (only the steps that change, appended onto the mission's existing " \
                         "plan) via Ai::Provisioning::AdaptationProposerService and routes it through the " \
                         "approval workflow as action_type project.adapt_<change_type>, so the operator's " \
                         "intervention policies decide auto-apply vs require-approval. Returns the plan id, " \
                         "its steps, and the approval routing outcome.",
            parameters: {
              mission_id: { type: "string", required: true, description: "Infrastructure mission ID" },
              change_type: { type: "string", required: true,
                             description: "One of: #{adapt_change_types.join(', ')}" },
              metric: { type: "string", required: false,
                        description: "Optional metric that motivated the change (e.g. p99_latency_ms)" },
              details: { type: "object", required: false,
                         description: "Optional structured payload merged into the adaptation signal " \
                                      "(observed, target, breach_pct, target_usd, correlation_id, …)" },
              proposed_change: { type: "object", required: false,
                                 description: "Legacy envelope: { change_type|kind: String, …details }. " \
                                              "Explicit change_type/metric/details take precedence." }
            }
          }
        }
      end

      # Resolved lazily (inside a method body, not at class-definition time) so
      # the tool never forces the proposer to autoload while the registry is
      # being built.
      def self.adapt_change_types
        ::Ai::Provisioning::AdaptationProposerService::REQUESTABLE_CHANGE_TYPES
      end

      protected

      def call(params)
        case params[:action]
        when "platform_provisioning_capture_brief"  then capture_brief(params)
        when "platform_provisioning_compose_plan"   then compose_plan(params)
        when "platform_provisioning_approve_plan"   then approve_plan(params)
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
        # Hybrid routing: recognized provisioning scenarios -> PlanComposerService,
        # novel/general intents -> MissionComposer. This is the concierge chat path,
        # so it MUST route identically to the worker-job + REST paths.
        composer = ::Ai::Missions::ComposerRouter.new(account: account, mission: mission).select
        result = composer.compose!

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

        # Single source of truth for the rich plan shape — same payload the
        # REST `/missions/:id/compose_plan` endpoint returns, so the chat card
        # and the deep-link page render identical data.
        snapshot = ::Ai::Provisioning::PlanSnapshotService.new(account: account).snapshot(plan: plan)
        success_result(snapshot.merge(mission_id: mission.id))
      rescue ::Ai::Provisioning::PlanComposerService::BriefMissingError,
             ::Ai::Provisioning::PlanComposerService::AgentMissingError,
             ::Ai::Missions::MissionComposer::CompositionError => e
        # MissionComposer (the novel-intent route) raises CompositionError for an
        # empty intent / no agent-bound skills / no valid steps — surface it as a
        # graceful error_result like the PlanComposerService failure modes.
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

      # Operator-initiated adaptation of a live mission. Delegates to
      # AdaptationProposerService#propose_change — the explicit-request seam
      # that funnels into the same internal path the ProjectSloSensor-driven
      # proposals use, so the resulting diff plan is always routed through
      # Ai::Autonomy::ApprovalWorkflowService as project.adapt_<change_type>.
      # This action never applies the change itself.
      def adapt(params)
        mission = find_mission!(params[:mission_id])
        legacy = hash_param(params[:proposed_change])

        change_type = (params[:change_type].presence ||
                       legacy["change_type"].presence ||
                       legacy["kind"].presence).to_s
        if change_type.blank?
          return error_result("change_type is required — one of: #{self.class.adapt_change_types.join(', ')}")
        end
        unless self.class.adapt_change_types.include?(change_type)
          return error_result(
            "Unknown change_type '#{change_type}' — must be one of: " \
            "#{self.class.adapt_change_types.join(', ')}"
          )
        end

        details = legacy.except("change_type", "kind").merge(hash_param(params[:details]))
        result = propose_adaptation(mission, change_type: change_type,
                                             metric: params[:metric], details: details)
        return error_result("Adaptation proposal failed for mission #{mission.id}") if result.nil?

        plan = result[:plan]
        unless plan
          return error_result(
            "No adaptation steps could be composed for change_type '#{change_type}' " \
            "on mission #{mission.id}"
          )
        end

        approval = result[:approval_request]
        success_result(
          mission_id: mission.id,
          change_type: result[:change_type],
          plan_id: plan.id,
          summary: adaptation_summary(plan, result[:change_type]),
          adaptation_plan: serialize_adaptation_plan(plan),
          approval: {
            requested: approval.present?,
            approval_request_id: approval.respond_to?(:id) ? approval.id : nil,
            status: approval.respond_to?(:status) ? approval.status : nil,
            action_type: "project.adapt_#{result[:change_type]}",
            auto_apply: result[:auto_apply] == true
          }
        )
      end

      # The proposer raises for a genuinely unknown change_type (already
      # screened above) and is otherwise best-effort; keep an MCP caller in a
      # clean envelope rather than bubbling a 500 out of the tool bridge.
      def propose_adaptation(mission, change_type:, metric:, details:)
        ::Ai::Provisioning::AdaptationProposerService
          .new(account: account, mission: mission)
          .propose_change(change_type: change_type, metric: metric, details: details)
      rescue ArgumentError
        raise
      rescue StandardError => e
        Rails.logger.warn(
          "[ProvisioningTool] adaptation proposal failed mission=#{mission.id} " \
          "change_type=#{change_type}: #{e.class}: #{e.message}"
        )
        nil
      end

      def hash_param(value)
        value = value.deep_stringify_keys if value.respond_to?(:deep_stringify_keys)
        value.is_a?(Hash) ? value : {}
      end

      def adaptation_summary(plan, change_type)
        steps = plan.steps.reload.to_a
        skills = steps.map { |s| step_skill(s) }.compact.uniq
        "Adaptation proposed (#{change_type}): #{steps.size} step#{'s' unless steps.size == 1}" \
          "#{skills.any? ? " — #{skills.join(', ')}" : ''}"
      end

      def serialize_adaptation_plan(plan)
        steps = plan.steps.reload.to_a.sort_by { |s| s.step_number.to_i }
        plan_data = plan.plan_data.is_a?(Hash) ? plan.plan_data : {}
        {
          id: plan.id,
          status: plan.respond_to?(:status) ? plan.status : nil,
          version: plan.respond_to?(:version) ? plan.version : nil,
          kind: plan_data["kind"],
          step_count: steps.size,
          steps: steps.map do |s|
            cfg = s.execution_config.is_a?(Hash) ? s.execution_config : {}
            {
              step_number: s.step_number,
              skill: step_skill(s),
              description: s.description,
              inputs: cfg["inputs"] || cfg[:inputs] || {},
              on_failure: cfg["on_failure"] || cfg[:on_failure],
              dependencies: Array(s.dependencies).map(&:to_i)
            }
          end
        }
      end

      def step_skill(step)
        cfg = step.execution_config.is_a?(Hash) ? step.execution_config : {}
        cfg["skill"] || cfg[:skill]
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
      # All advances delegate to OrchestratorService so status (draft→active),
      # phase_history bookkeeping, dispatch, and approval gate semantics stay
      # in one place. Direct mission.update!(current_phase: …) here used to
      # produce hybrid states (e.g. current_phase=execute, status=draft) that
      # left the orchestrator unaware of an in-flight mission.

      def orchestrator_for(mission)
        ::Ai::Missions::OrchestratorService.new(mission: mission)
      end

      def advance_to_compose_plan!(mission)
        return unless mission.current_phase == "capture_intent"
        orchestrator_for(mission).transition_to!("compose_plan")
      end

      def advance_to_review_plan!(mission)
        return unless %w[capture_intent compose_plan].include?(mission.current_phase)
        orchestrator_for(mission).transition_to!("review_plan")
      end

      # Approval — creates Ai::MissionApproval record AND dispatches the
      # execute-phase worker job via OrchestratorService#advance!.
      def advance_past_review_gate!(mission)
        return unless mission.current_phase == "review_plan"
        orchestrator_for(mission).handle_approval!(
          gate: "plan_review",
          user: user,
          decision: "approved"
        )
      end

      # Rejection — creates Ai::MissionApproval(decision="rejected") record
      # AND rolls phase back per the template's rejection_mappings.
      def send_back_to_compose!(mission)
        return unless mission.current_phase == "review_plan"
        orchestrator_for(mission).handle_approval!(
          gate: "plan_review",
          user: user,
          decision: "rejected"
        )
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
