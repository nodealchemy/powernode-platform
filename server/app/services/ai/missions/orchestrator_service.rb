# frozen_string_literal: true

module Ai
  module Missions
    class OrchestratorService
      class OrchestrationError < StandardError; end

      CLEANUP_PHASES = %w[completed cancelled].freeze

      attr_reader :mission

      def initialize(mission:)
        @mission = mission
      end

      # Lazy account lookup so callers can construct the orchestrator from
      # contexts that don't yet (or never will) resolve `mission.account` —
      # e.g. SkillCompositionRunner unit tests pass a duck-typed mission
      # double that only stubs the methods broadcast_step_event! actually
      # touches. Re-evaluating on each call would be wasteful, so we
      # memoize on first hit.
      def account
        return @account if defined?(@account)
        @account = mission.account
      end

      def start!
        raise OrchestrationError, "Mission must be in draft status to start" unless mission.status == "draft"
        raise OrchestrationError, "Mission must have an objective" if mission.objective.blank? && mission.mission_type == "development"

        create_conversation! if mission.conversation_id.blank?

        first_phase = mission.phases_for_type.first
        ActiveRecord::Base.transaction do
          mission.update!(status: "active", started_at: Time.current)
          transition_to_phase!(first_phase)
        end

        dispatch_phase_job!

        mission
      end

      def advance!(result: {}, expected_phase: nil)
        # Guard against stale Sidekiq retries: if the caller specifies
        # which phase it expects, reject the advance if the mission has
        # already moved past that phase.
        if expected_phase.present? && mission.current_phase != expected_phase
          Rails.logger.warn(
            "Stale advance rejected for mission #{mission.id}: " \
            "expected phase #{expected_phase}, current phase #{mission.current_phase}"
          )
          return mission
        end

        # F-d (IMP 019fe5d0-ed2d): a phase's artifact must exist before the
        # mission may leave it. Observed live (dryrun 20260809b): an advance
        # out of compose_plan succeeded with NO plan in existence, handing
        # review_plan nothing to review. Scoped to infrastructure missions —
        # other mission types carry different artifacts.
        assert_phase_artifact!

        record_phase_exit(result)

        next_phase = determine_next_phase
        if next_phase.nil? || next_phase == "completed"
          complete_mission!(result)
        else
          transition_to_phase!(next_phase)
          dispatch_phase_job! unless mission.awaiting_approval?
        end

        mission
      end

      def handle_approval!(gate:, user:, decision:, comment: nil, selected_feature: nil, prd_modifications: nil)
        # Translation is idempotent — if `gate` is already a valid gate
        # name (e.g. caller already translated), passing it through the
        # canonical mapping returns it unchanged.
        gate_name = ::Ai::MissionApproval.gate_for_phase(gate, mission: mission)

        approval = mission.approvals.create!(
          account: account,
          user: user,
          gate: gate_name,
          decision: decision,
          comment: comment,
          metadata: { selected_feature: selected_feature, prd_modifications: prd_modifications }.compact
        )

        if decision == "approved"
          if selected_feature.present?
            mission.update!(selected_feature: selected_feature)
          end

          # Approval-unification (flag-gated): when this mission is routed
          # through Ai::Approvals::Gateway, a governance ApprovalRequest is the
          # source of truth for the gate. Resolving it cascades back via
          # Ai::Mission#on_approval_decision → advance!, so we resolve and
          # return here instead of running the legacy second-signature/advance!
          # path. Default OFF: gateway_request_for is nil unless governance is
          # present AND the opt-in flag is set, in which case the legacy code
          # below runs byte-for-byte unchanged.
          if (req = gateway_request_for(gate_name))
            # The gateway chain does not enforce distinct approvers, so guard a
            # repeat signature from the same user (e.g. second-signature gates).
            return mission if same_user_already_approved?(req, user)

            Ai::Approvals::Gateway.new(account: account)
                                  .resolve!(request: req, decision: "approved", by: user, comments: comment)
            return mission
          end

          # M4 second-signature gate — Business+ plans require two distinct
          # approvers at the `handoff` phase. The first approval is recorded
          # but the mission stays at `handoff` until a different user also
          # approves. Free/Pro tiers (predicate returns false) skip this
          # branch entirely and advance after the single approval below.
          if mission.requires_second_signature? &&
             mission.distinct_approver_count(gate_name) < 2
            Rails.logger.info(
              "[OrchestratorService] mission=#{mission.id} second-signature gate: " \
              "first approval recorded by user_id=#{user.id} at gate=#{gate_name} — " \
              "awaiting second distinct approver"
            )
            return mission
          end

          advance!(result: { approval_id: approval.id })
        else
          # Gateway-routed rejection: resolve the governance ApprovalRequest,
          # which cascades back via Ai::Mission#on_approval_decision →
          # reject_gate!. Falls through to the legacy rejection bookkeeping when
          # routing is off (default).
          if (req = gateway_request_for(gate_name))
            Ai::Approvals::Gateway.new(account: account)
                                  .resolve!(request: req, decision: "rejected", by: user, comments: comment)
            return mission
          end

          handle_rejection!(gate: mission.current_phase, comment: comment)
        end

        mission
      end

      # Public rejection entry used by Ai::Mission#on_approval_decision when a
      # gateway-routed ApprovalRequest is rejected/expired. Routes through the
      # same legacy rejection bookkeeping (rollback mapping + phase job
      # dispatch) so both paths roll a gate back identically.
      def reject_gate!(comment: nil)
        handle_rejection!(gate: mission.current_phase, comment: comment)
        mission
      end

      # Public, idempotent phase jump that mirrors the bookkeeping of
       # advance!/start! without forcing a worker-job dispatch. Used by the
       # chat-tool path (Ai::Tools::ProvisioningTool) which advances phases
       # interactively as the operator refines the brief and plan — the
       # interactive UX doesn't want to fire the phase job until an
       # approval gate clears.
       #
       # Why this exists: callers used to update current_phase via raw
       # mission.update!, which bypassed status flip (draft→active),
       # phase_history bookkeeping, and approval gate semantics. That
       # produced hybrid states like (current_phase=execute, status=draft)
       # where the orchestrator never knew the mission was active.
      def transition_to!(target_phase, dispatch: false)
        target = target_phase.to_s
        return mission if mission.current_phase == target

        ActiveRecord::Base.transaction do
          if mission.status == "draft"
            mission.update!(
              status: "active",
              started_at: mission.started_at || Time.current
            )
          end
          record_phase_exit({}) if mission.current_phase.present?
          transition_to_phase!(target)
        end

        dispatch_phase_job! if dispatch && !mission.awaiting_approval?
        mission
      end

      def cancel!(reason: nil)
        mission.update!(
          status: "cancelled",
          error_message: reason,
          completed_at: Time.current
        )
        dispatch_cleanup_job!
        mission
      end

      def pause!
        raise OrchestrationError, "Mission must be active to pause" unless mission.status == "active"

        mission.update!(status: "paused")
        mission
      end

      def resume!
        raise OrchestrationError, "Mission must be paused to resume" unless mission.status == "paused"

        mission.update!(status: "active")
        dispatch_phase_job! unless mission.awaiting_approval?
        mission
      end

      def retry_phase!
        raise OrchestrationError, "Mission must be active or failed" unless %w[active failed].include?(mission.status)

        mission.update!(status: "active", error_message: nil, error_details: {})
        dispatch_phase_job!
        mission
      end

      # Emit a step-level `provisioning_step_changed` event for the Plan Review
      # / Execution streaming UI. Called by SkillCompositionRunner (and any
      # alternative step processors) so the OrchestratorService is the single
      # surface that announces step transitions for a mission. Safe to invoke
      # from any thread / background job — broadcast failures are logged but
      # never raised so we don't break the runner's transaction.
      #
      # @param step [#id, #step_number, Hash, String] step record, hash payload, or id
      # @param status [String] one of: started, completed, failed, executing,
      #        rolled_back, awaiting_approval (the step parked on an autonomy
      #        approval — SkillCompositionRunner::PARKED_STATUS)
      # @param outputs [Hash, nil] optional outputs hash (omitted from payload when nil/blank)
      # @param error [String, nil] optional error message (omitted when blank)
      # @param extra [Hash] optional supplemental fields merged into the payload
      #        (used by SkillCompositionRunner to surface runner_id + skill name)
      # @return [Hash] the broadcast payload (useful for tests + logging)
      def broadcast_step_event!(step:, status:, outputs: nil, error: nil, extra: {})
        payload = {
          mission_id: mission.id,
          step_id: extract_step_id(step),
          step_number: extract_step_number(step),
          status: status.to_s
        }
        payload[:outputs] = outputs if outputs.is_a?(Hash) && outputs.any?
        payload[:error]   = error   if error.is_a?(String) && !error.strip.empty?
        payload.merge!(extra) if extra.is_a?(Hash) && extra.any?

        ::MissionChannel.broadcast_mission_event(mission.id, "provisioning_step_changed", payload)
        payload
      rescue StandardError => e
        Rails.logger.warn(
          "[OrchestratorService] broadcast_step_event failed for mission #{mission.id}: " \
          "#{e.class}: #{e.message}"
        )
        nil
      end

      private

      # Per-phase artifact preconditions for infrastructure missions (F-d).
      # capture_intent's artifact is a COMPLETE brief (present, and the
      # capture endpoint's recorded brief_missing_fields empty);
      # compose_plan's is the stamped plan pointer. Gates (review_plan,
      # handoff) advance through handle_approval!, whose precondition IS the
      # approval; other phases carry no compose-side artifact to assert.
      def assert_phase_artifact!
        return unless mission.mission_type.to_s == "infrastructure"

        cfg = mission.configuration.is_a?(Hash) ? mission.configuration : {}
        case mission.current_phase.to_s
        when "capture_intent"
          if cfg["brief"].blank?
            raise OrchestrationError,
                  "cannot advance out of capture_intent: no brief has been captured"
          end
          missing = Array(cfg["brief_missing_fields"]).map(&:to_s).reject(&:blank?)
          if missing.any?
            raise OrchestrationError,
                  "cannot advance out of capture_intent: brief is missing #{missing.join(', ')}"
          end
        when "compose_plan"
          if cfg.dig("plan", "plan_id").blank?
            raise OrchestrationError,
                  "cannot advance out of compose_plan: no composed plan (plan_id absent) — " \
                  "review_plan would have nothing to review"
          end
        end
      end

      # Extract a stable step identifier from whatever shape the caller hands us.
      # Accepts AR records (Ai::GoalPlanStep), Hashes ({ step_id:, step_number: }),
      # or bare String/UUID ids.
      def extract_step_id(step)
        return step if step.is_a?(String)
        return step.id if step.respond_to?(:id) && !step.is_a?(Hash)
        if step.is_a?(Hash)
          return step[:step_id] || step["step_id"] || step[:id] || step["id"]
        end
        nil
      end

      def extract_step_number(step)
        return step.step_number if step.respond_to?(:step_number) && !step.is_a?(Hash)
        if step.is_a?(Hash)
          return step[:step_number] || step["step_number"]
        end
        nil
      end


      def transition_to_phase!(phase)
        mission.update!(current_phase: phase)
        record_phase_entry(phase)
        open_gateway_gate!(phase) if mission.awaiting_approval?
      end

      def record_phase_entry(phase)
        history = mission.phase_history || []
        history << { phase: phase, entered_at: Time.current.iso8601 }
        mission.update!(phase_history: history)
      end

      def record_phase_exit(result)
        history = mission.phase_history || []
        current_entry = history.last
        if current_entry
          current_entry["exited_at"] = Time.current.iso8601
          current_entry["result"] = result if result.present?
          mission.update!(phase_history: history)
        end
      end

      def determine_next_phase
        phases = mission.phases_for_type
        current_index = phases.index(mission.current_phase)
        return nil unless current_index

        next_index = current_index + 1
        return nil if next_index >= phases.length

        next_phase = phases[next_index]

        skip_config = mission.phase_config["skip_phases"] || []
        while skip_config.include?(next_phase) && next_index < phases.length - 1
          next_index += 1
          next_phase = phases[next_index]
        end

        next_phase
      end

      def dispatch_phase_job!
        phase = mission.current_phase
        return if mission.awaiting_approval?

        # Canonical land path (flag-gated, default OFF). When a mission enters the
        # merging phase, route the merge through the unified Ai::Land service via a
        # polymorphic land source instead of dispatching the legacy
        # AiMissionMergeJob. Intercepting at phase ENTRY (not in handle_approval!)
        # catches both the gateway-routed and legacy approval paths, since both
        # advance the mission into "merging". Flag OFF -> falls through to the
        # legacy merge-job dispatch below, byte-for-byte unchanged.
        if phase == "merging" && Ai::Land::Feature.mission_landing_enabled?(account: account)
          Ai::Land::ApprovalBinding.request_land_approval(
            source: mission,
            source_branch: mission.branch_name,
            target_branch: mission.base_branch.presence || mission.repository&.default_branch || "main",
            description: "Land mission #{mission.name} (#{mission.branch_name})",
            requested_by: nil
          )
          return
        end

        job_class = job_class_for_phase(phase)
        return unless job_class

        Rails.logger.info("Dispatching #{job_class} for mission #{mission.id}")
        WorkerJobService.enqueue_job(job_class, args: [{
          "mission_id" => mission.id,
          "account_id" => account.id
        }], queue: "ai_execution")
      end

      def dispatch_cleanup_job!
        Rails.logger.info("Dispatching cleanup for mission #{mission.id}")
        WorkerJobService.enqueue_job("AiMissionCleanupJob", args: [{
          "mission_id" => mission.id,
          "account_id" => account.id
        }], queue: "maintenance")
      end

      def complete_mission!(result)
        mission.update!(
          status: "completed",
          current_phase: "completed",
          completed_at: Time.current
        )
        dispatch_cleanup_job!
      end

      def handle_rejection!(gate:, comment:)
        rollback_phase = resolve_rejection_target(gate)
        if rollback_phase
          transition_to_phase!(rollback_phase)
          dispatch_phase_job!
        end
      end

      def resolve_rejection_target(gate)
        if mission.mission_template.present?
          mission.mission_template.rejection_mapping_for(gate)
        end
      end

      def job_class_for_phase(phase)
        custom = find_custom_phase_config(phase)
        custom&.dig("job_class")
      end

      def find_custom_phase_config(phase_key)
        if mission.custom_phases.present?
          mission.custom_phases.find { |p| p["key"] == phase_key }
        elsif mission.mission_template.present?
          mission.mission_template.phases&.find { |p| p["key"] == phase_key }
        end
      end

      # Kept as a thin shim for any callers still using the orchestrator's
      # method directly. Delegates to the canonical mapping on the model
      # — same answer either way.
      def gate_for_phase(phase)
        ::Ai::MissionApproval.gate_for_phase(phase, mission: mission)
      end

      # ==================== Approval-unification (flag-gated) ====================

      # Whether this mission's approval gates are routed through the canonical
      # Ai::Approvals::Gateway. Requires BOTH a governance extension (so an
      # ApprovalRequest can actually be created) AND an explicit opt-in flag,
      # set per-mission (configuration) or account-wide (settings). Default OFF:
      # when false every legacy approval path runs byte-for-byte unchanged.
      def gateway_routing?
        return false unless Ai::Approvals::Gateway.governance_enabled?

        mission.configuration["approvals_via_gateway"] ||
          account.settings&.dig("ai", "approvals_via_gateway")
      end

      # The open (pending) gateway ApprovalRequest for a given gate, when
      # routing is on. Matches on source (this mission) + action_type (the gate
      # name stamped into request_data by Gateway#request!). nil when routing is
      # off or no request is open.
      def gateway_request_for(gate)
        return nil unless gateway_routing?

        Ai::ApprovalRequest
          .for_source("Ai::Mission", mission.id)
          .where(status: "pending")
          .where("request_data ->> 'action_type' = ?", gate.to_s)
          .order(created_at: :desc)
          .first
      end

      # The gateway chain does not enforce distinct approvers; this guards a
      # repeat signature from the same user at a multi-signature gate.
      def same_user_already_approved?(request, user)
        request.decisions.where(approver_id: user.id, decision: "approved").exists?
      end

      # Opens a governance ApprovalRequest when transitioning into an approval
      # gate phase under gateway routing. Idempotent (skips when one is already
      # open) and best-effort: any failure is logged, never raised, so the phase
      # transition itself can never be broken by the gate.
      def open_gateway_gate!(phase)
        return unless gateway_routing?

        gate = ::Ai::MissionApproval.gate_for_phase(phase, mission: mission)
        return unless ::Ai::MissionApproval::GATES.include?(gate.to_s)
        return if gateway_request_for(gate).present?

        required = mission.requires_second_signature? ? 2 : 1
        Ai::Approvals::Gateway.new(account: account).request!(
          approvable: mission,
          kind: gate,
          required_approvals: required,
          requested_by: mission.created_by,
          request_data: { mission_id: mission.id, phase: phase.to_s }
        )
      rescue StandardError => e
        Rails.logger.warn(
          "[OrchestratorService] open_gateway_gate! failed for mission #{mission.id}: " \
          "#{e.class}: #{e.message}"
        )
      end

      def create_conversation!
        return unless defined?(Ai::Conversation)

        provider = account.ai_providers.first
        return unless provider

        conversation = account.ai_conversations.create!(
          user: mission.created_by,
          ai_provider_id: provider.id,
          title: "Mission: #{mission.name}",
          status: "active",
          conversation_type: "agent",
          message_count: 0,
          total_tokens: 0,
          total_cost: 0
        )
        mission.update!(conversation_id: conversation.id)
      rescue StandardError => e
        Rails.logger.warn("Failed to create mission conversation: #{e.message}")
      end
    end
  end
end
