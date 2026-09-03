# frozen_string_literal: true

# Internal endpoints invoked by the worker's three provisioning phase jobs
# (capture_intent, compose_plan, execute). The worker is API-only with the
# server, so each phase job POSTs here, the controller invokes the matching
# server-side service, and returns the result.
class Api::V1::Internal::Ai::ProvisioningController < Api::V1::Internal::InternalBaseController
  before_action :load_mission

  # POST /api/v1/internal/ai/provisioning/missions/:mission_id/capture_intent
  def capture_intent
    natural_language = params[:natural_language].presence || @mission.objective.to_s
    prior_brief      = params[:prior_brief]

    service = ::Ai::Provisioning::IntentCaptureService.new(
      account: @mission.account,
      user: @mission.created_by,
      conversation: @mission.conversation
    )
    result = service.capture(natural_language: natural_language, prior_brief: prior_brief)

    persist_brief(result)

    # F6 (IMP 019fe4c5-03a4): the phase advances ITSELF when its completion
    # criteria hold — a complete brief. With fields missing the mission stays
    # here awaiting clarification, and what's missing is recorded on the
    # config so the orchestrator's artifact gate (F-d) and any UI can see it.
    missing = Array(result[:missing_fields] || result["missing_fields"])
    advanced = false
    if missing.empty? && @mission.current_phase.to_s == "capture_intent"
      ::Ai::Missions::OrchestratorService.new(mission: @mission)
        .advance!(expected_phase: "capture_intent")
      advanced = true
    end

    render_success(result.merge(advanced: advanced, phase: @mission.reload.current_phase))
  rescue StandardError => e
    Rails.logger.error("[Internal::Ai::Provisioning#capture_intent] #{e.class}: #{e.message}")
    render_error("Capture intent failed: #{e.message}", status: :unprocessable_content)
  end

  # POST /api/v1/internal/ai/provisioning/missions/:mission_id/compose_plan
  #
  # Hybrid composer routing. A side-effect-free predicate inspects the brief
  # and picks ONE composer up front — we never try-then-discard, because
  # PlanComposerService persists on success (a discarded attempt would leak a
  # real plan). A recognized provisioning scenario routes to the constrained
  # PlanComposerService; a novel/general intent routes to the LLM-driven
  # Ai::Missions::MissionComposer. Both stamp the same
  # mission.configuration["plan"]["plan_id"], so #execute is unchanged. A nil
  # return means the account hit its LLM cost cap — we surface plan_id: nil
  # rather than falling back to the other (also cost-capped) composer.
  def compose_plan
    # Hybrid routing (shared with the concierge tool + public REST paths):
    # recognized provisioning scenarios -> PlanComposerService, novel/general
    # intents -> MissionComposer. Both stamp the same plan_id pointer.
    service = ::Ai::Missions::ComposerRouter.new(account: @mission.account, mission: @mission).select
    plan = service.compose!

    # PlanComposerService returns `{ clarification_needed: true, ... }` — NOT a
    # plan — when the account has 2+ providers and the brief carries no usable
    # preferred_provider. That Hash must never reach persist_plan_pointer /
    # `plan&.id`: it raises NoMethodError, the blanket rescue below turns it into
    # a 422 reading "undefined method `id'", and AiProvisioningComposePlanJob
    # burns its retries and leaves the mission dead in compose_plan. Net effect
    # before this guard: NO account with more than one configured provider could
    # compose a provisioning plan at all (IMP 019fe1d8, found by the
    # platform-autonomy-dryrun P1 baseline against a 2-provider account).
    #
    # Handled exactly as the PUBLIC path does
    # (concerns/ai/missions/plan_composition_actions.rb) so the two cannot drift.
    if plan.is_a?(Hash) && plan[:clarification_needed]
      return render_error(
        plan[:message] || "Multiple providers configured — clarify before composing",
        status: :unprocessable_content,
        details: plan.except(:clarification_needed)
      )
    end

    # F-c (IMP 019fe5d0-d68f): a nil composer result previously rendered
    # SUCCESS with plan_id: null and the mission died silently in
    # compose_plan. A phase that produced no artifact has not completed —
    # say so. The cost-cap nil carries its payload (UpgradeRequiredCard);
    # any other nil is a composition failure.
    if plan.nil?
      cap = service.respond_to?(:cap_exceeded_payload) ? service.cap_exceeded_payload : nil
      reason = if cap
                 "compose_plan blocked: LLM cost cap exceeded " \
                 "(spent $#{cap[:spent] || cap['spent']}, cap $#{cap[:cap] || cap['cap']})"
               else
                 "compose_plan produced no plan (composer returned nil — decomposition " \
                 "failure or parse miss; see logs)"
               end
      @mission.update!(error_message: reason)
      Rails.logger.error("[Internal::Ai::Provisioning#compose_plan] mission=#{@mission.id} #{reason}")
      return render_error(reason, status: :unprocessable_content,
                          details: cap ? { requires_upgrade: true }.merge(cap.to_h) : {})
    end

    persist_plan_pointer(plan)

    # F6: compose advances itself once the plan pointer is stamped — the
    # artifact gate (F-d) it passes through is the same one that blocks a
    # bare manual advance.
    advanced = false
    if @mission.reload.configuration.dig("plan", "plan_id").present? &&
       @mission.current_phase.to_s == "compose_plan"
      ::Ai::Missions::OrchestratorService.new(mission: @mission)
        .advance!(expected_phase: "compose_plan")
      advanced = true
    end

    render_success(plan_id: plan&.id, mission_id: @mission.id,
                   advanced: advanced, phase: @mission.reload.current_phase)
  rescue StandardError => e
    Rails.logger.error("[Internal::Ai::Provisioning#compose_plan] #{e.class}: #{e.message}")
    render_error("Compose plan failed: #{e.message}", status: :unprocessable_content)
  end

  # POST /api/v1/internal/ai/provisioning/missions/:mission_id/execute
  #
  # Canonical entry point for kicking off a provisioning run. Reached by the
  # AiProvisioningExecuteJob worker job after the approve gate advances the
  # mission past `review_plan`. This is the ONLY path to execution — there
  # is no `platform_provisioning_execute` MCP tool action (was removed; the
  # tool variant raced with this path and double-provisioned).
  def execute
    plan = resolve_plan!
    return render_error("No plan available for mission", status: :unprocessable_content) unless plan

    # M1 Self-Serve Hardening — gate execution on subscription quota. On
    # denial, surface a structured upgrade payload the frontend can render.
    # Previously the gate lived only in the (now-removed) tool action, so
    # the worker-job path was bypassing it.
    quota = Powernode::BillingBridge.check_provisioning_quota(account: @mission.account, mission: @mission)
    unless quota[:allowed]
      payload = quota[:payload]

      # A real plan verdict is a terminal, well-understood answer: 200 + the
      # upgrade payload, which the caller renders as an upgrade card.
      #
      # A DEGRADED denial is not a verdict — the quota check itself failed and
      # the bridge closed rather than provisioning unmetered. Rendering that as
      # success strands the mission silently: AiProvisioningExecuteJob only
      # calls report_failure on `success: false`, so a 200 here leaves the
      # mission un-advanced, un-failed, and unretried, with nothing but a green
      # "kicked off" log carrying a nil runner_id. Say it failed.
      if payload[:reason] == ::Powernode::BillingBridge::DEGRADED_QUOTA_REASON
        message = "Execute blocked: provisioning quota could not be checked"
        @mission.update!(error_message: message)
        Rails.logger.error("[Internal::Ai::Provisioning#execute] mission=#{@mission.id} #{message}")
        return render_error(message, status: :unprocessable_content,
                            details: payload.merge(mission_id: @mission.id))
      end

      return render_success(payload.merge(mission_id: @mission.id))
    end

    runner = ::Ai::Provisioning::SkillCompositionRunner.new(
      account: @mission.account,
      mission: @mission,
      plan: plan
    )
    result = runner.execute!
    render_success(result.merge(mission_id: @mission.id))
  rescue StandardError => e
    Rails.logger.error("[Internal::Ai::Provisioning#execute] #{e.class}: #{e.message}")
    render_error("Execute failed: #{e.message}", status: :unprocessable_content)
  end

  # POST /api/v1/internal/ai/provisioning/missions/:mission_id/verify
  #
  # Phase-4 entry point. For M2 the verification is a stub that records a
  # synthetic SLO check pass — the long-lived ProjectSloSensor (Slice A) does
  # the real ongoing sampling once the mission is in the `adapting` phase.
  # On success we hand control back to the orchestrator which advances to
  # `handoff`. On failure we leave the mission paused at `verify` so an
  # operator can retry or abort.
  def verify
    slo_targets = (@mission.configuration.is_a?(Hash) ? @mission.configuration["slo_targets"] : nil) || {}

    # Real verification (F2, IMP 019fe4c4-c7c4) — plan/step/live-provider
    # reconciliation via VerificationService. The old stub marked every
    # mission healthy and advanced; live it blessed a phantom instance in
    # 0.23s. Verification that cannot block is theater, so an unhealthy
    # result FAILS THE PHASE: no advance, error recorded, operator retries
    # the phase (or cancels) once the divergence is addressed.
    verification = ::Ai::Provisioning::VerificationService
                     .new(account: @mission.account, mission: @mission).verify
    healthy = verification[:healthy]
    checked_at = Time.current.iso8601

    record_verification(
      slo_targets: slo_targets, healthy: healthy, checked_at: checked_at,
      checks: verification[:checks]
    )

    if healthy
      orchestrator = ::Ai::Missions::OrchestratorService.new(mission: @mission)
      orchestrator.advance!(
        result: { verification: { healthy: healthy, checked_at: checked_at } },
        expected_phase: "verify"
      )
    else
      failing = verification[:checks].reject { |c| c[:ok] }
      summary = failing.first(3).map { |c| "#{c[:name]}: #{c[:detail]}" }.join("; ")
      Rails.logger.error(
        "[Internal::Ai::Provisioning#verify] mission=#{@mission.id} UNHEALTHY " \
          "(#{failing.size} failing check(s)): #{summary}"
      )
      @mission.update!(error_message: "verification failed: #{summary}"[0, 500])
    end

    render_success(
      mission_id: @mission.id,
      healthy: healthy,
      checks: verification[:checks],
      slo_targets: slo_targets,
      checked_at: checked_at,
      phase: @mission.reload.current_phase
    )
  rescue StandardError => e
    Rails.logger.error("[Internal::Ai::Provisioning#verify] #{e.class}: #{e.message}")
    render_error("Verify failed: #{e.message}", status: :unprocessable_content)
  end

  # POST /api/v1/internal/ai/provisioning/missions/:mission_id/steps/:step_id/execute
  #
  # Invoked by AiProvisioningStepJob — one POST per step in the DAG layer
  # the runner just dispatched. Loads the step (account-scoped through its
  # plan), reattaches it to a runner instance, and runs execute_step!.
  # The optional runner_id passed by the worker is preserved on the runner
  # so step-progress broadcasts include the originating run identifier.
  def execute_step
    step = resolve_step!(params[:step_id])
    return render_error("Step not found", status: :not_found) unless step

    plan = step.plan
    return render_error("Step is not bound to a plan", status: :unprocessable_content) unless plan

    runner = ::Ai::Provisioning::SkillCompositionRunner.new(
      account: @mission.account,
      mission: @mission,
      plan: plan
    )
    runner.instance_variable_set(:@runner_id, params[:runner_id]) if params[:runner_id].present?

    result = runner.execute_step!(step)
    render_success(result.merge(mission_id: @mission.id, step_id: step.id))
  rescue StandardError => e
    Rails.logger.error("[Internal::Ai::Provisioning#execute_step] #{e.class}: #{e.message}")
    render_error("Step execute failed: #{e.message}", status: :unprocessable_content)
  end

  private

  # Account-scopes the step lookup through its plan to prevent cross-account
  # access via leaked step_ids. (Steps don't have account_id directly — the
  # join through ai_goal_plans.account_id is the only safe scope.)
  def resolve_step!(step_id)
    return nil if step_id.blank?
    ::Ai::GoalPlanStep
      .joins(:plan)
      .where(ai_goal_plans: { account_id: @mission.account_id })
      .find_by(id: step_id)
  end

  def load_mission
    @mission = ::Ai::Mission.find_by(id: params[:mission_id])
    return render_error("Mission not found", status: :not_found) unless @mission
  end

  def persist_brief(result)
    return unless @mission && result.is_a?(Hash)

    cfg = @mission.configuration.is_a?(Hash) ? @mission.configuration.deep_dup : {}
    cfg["brief"] = result[:brief] || result["brief"] || cfg["brief"]
    # Recorded so the orchestrator's capture_intent artifact gate (F-d) and
    # any surface can see WHY the phase is holding; cleared once complete.
    cfg["brief_missing_fields"] = Array(result[:missing_fields] || result["missing_fields"]).map(&:to_s)
    @mission.update_columns(configuration: cfg) if cfg["brief"].present?
  end

  def persist_plan_pointer(plan)
    return unless @mission && plan&.respond_to?(:id)

    cfg = @mission.configuration.is_a?(Hash) ? @mission.configuration.deep_dup : {}
    cfg["plan"] ||= {}
    cfg["plan"]["plan_id"] = plan.id
    @mission.update_columns(configuration: cfg)
  end

  def resolve_plan!
    plan_id = @mission.configuration.is_a?(Hash) ? @mission.configuration.dig("plan", "plan_id") : nil
    return ::Ai::GoalPlan.find_by(id: plan_id) if plan_id.present?

    # Fallback: most-recent approved plan for this mission's goal pointer (if any).
    nil
  end

  # Persist the verification result on the mission's configuration so it
  # rides through the phase_history alongside the phase exit and is visible
  # to operators / the adapting phase consumers.
  def record_verification(slo_targets:, healthy:, checked_at:, checks: [])
    return unless @mission

    cfg = @mission.configuration.is_a?(Hash) ? @mission.configuration.deep_dup : {}
    cfg["verification"] = {
      "healthy" => healthy,
      "checked_at" => checked_at,
      "slo_targets" => slo_targets,
      "checks" => checks.map { |c| c.deep_stringify_keys }
    }
    @mission.update_columns(configuration: cfg)
  end

end
