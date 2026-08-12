# frozen_string_literal: true

module Ai
  class Mission < ApplicationRecord
    self.table_name = "ai_missions"

    include Auditable

    # ==================== Constants ====================
    MISSION_TYPES = %w[development research operations infrastructure agent_fleet content_production custom].freeze

    STATUSES = %w[draft active paused completed failed cancelled].freeze
    TERMINAL_STATUSES = %w[completed failed cancelled].freeze

    # ==================== Associations ====================
    belongs_to :account
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id"
    belongs_to :repository, class_name: "Devops::GitRepository", foreign_key: "repository_id", optional: true
    belongs_to :team, class_name: "Ai::AgentTeam", foreign_key: "team_id", optional: true
    belongs_to :conversation, class_name: "Ai::Conversation", foreign_key: "conversation_id", optional: true
    belongs_to :risk_contract, class_name: "Ai::CodeFactory::RiskContract", foreign_key: "risk_contract_id", optional: true
    belongs_to :ralph_loop, class_name: "Ai::RalphLoop", foreign_key: "ralph_loop_id", optional: true
    belongs_to :review_state, class_name: "Ai::CodeFactory::ReviewState", foreign_key: "review_state_id", optional: true
    belongs_to :mission_template, class_name: "Ai::MissionTemplate", foreign_key: "mission_template_id", optional: true
    # Self-Serve Hardening M4 Slice A — optional per-team isolation pointer.
    # Backed by an extension-provided `Account::TeamDelegation` model. Leading `::` keeps
    # the constant resolved at the top level when that extension is loaded; when the
    # extension is absent, this column stays NULL on every row.
    belongs_to :delegation,
               class_name: "::Account::TeamDelegation",
               foreign_key: "delegation_id",
               inverse_of: :missions,
               optional: true

    has_many :approvals, class_name: "Ai::MissionApproval", foreign_key: "mission_id", dependent: :destroy

    # ==================== Validations ====================
    validates :name, presence: true, length: { maximum: 255 }
    validates :mission_type, presence: true, inclusion: { in: MISSION_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    # "completed" is a universal terminal sentinel written by
    # OrchestratorService#complete_mission! for every mission type, even when a
    # template's own phase pipeline ends earlier (e.g. reap, adapting). Allow it
    # alongside the template-defined phases so missions can actually finish.
    validates :current_phase, inclusion: { in: ->(m) { m.phases_for_type + %w[completed] } }, allow_nil: true
    validates :deployed_port, numericality: { only_integer: true, greater_than_or_equal_to: 6000, less_than_or_equal_to: 6199 }, allow_nil: true
    validate :repository_required_for_development

    # ==================== Scopes ====================
    scope :active, -> { where(status: "active") }
    scope :draft, -> { where(status: "draft") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :terminal, -> { where(status: TERMINAL_STATUSES) }
    scope :in_progress, -> { where(status: %w[active paused]) }
    scope :development, -> { where(mission_type: "development") }
    scope :research, -> { where(mission_type: "research") }
    scope :operations, -> { where(mission_type: "operations") }
    scope :infrastructure, -> { where(mission_type: "infrastructure") }
    scope :content_production, -> { where(mission_type: "content_production") }
    scope :recent, -> { order(created_at: :desc) }
    scope :with_deployment, -> { where.not(deployed_port: nil) }

    # ==================== Callbacks ====================
    before_validation :set_defaults, on: :create
    before_save :calculate_duration, if: -> { completed_at_changed? && completed_at.present? }
    after_save :broadcast_status_update, if: :saved_change_to_status?
    after_save :broadcast_phase_update, if: :saved_change_to_current_phase?
    # M5 conversation unification: provisioning missions tag their associated
    # conversation so the operator UI's chat sidebar can surface them in a
    # dedicated "Provisioning" group alongside agent + workspace conversations.
    after_save :tag_conversation_as_provisioning, if: -> {
      saved_change_to_conversation_id? && conversation_id.present? && mission_type == "infrastructure"
    }
    after_save :post_milestone_to_conversation, if: -> {
      saved_change_to_current_phase? && conversation_id.present?
    }

    # ==================== Instance Methods ====================

    def development?
      mission_type == "development"
    end

    def research?
      mission_type == "research"
    end

    def operations?
      mission_type == "operations"
    end

    def infrastructure?
      mission_type == "infrastructure"
    end

    def content_production?
      mission_type == "content_production"
    end

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def awaiting_approval?
      approval_gate_phases.include?(current_phase)
    end

    def approval_gate_phases
      if custom_phases.present?
        custom_phases.select { |p| p["requires_approval"] }.map { |p| p["key"] }
      elsif mission_template.present?
        mission_template.approval_gate_keys
      else
        []
      end
    end

    def current_gate
      current_phase if awaiting_approval?
    end

    # The blast-radius marker this mission stamps onto everything it creates
    # (F3, IMP 019fe4c4-e813): PlanComposerService threads it into the
    # provisioning step as `name_prefix`, the executor prefixes node names, and
    # instance names derive from those. Explicit `configuration.name_prefix`
    # wins; a dryrun run id derives the charter's prefix; anything else means
    # the mission has no prefix opinion and returns nil.
    #
    # It lives on the mission — not in the composer that first needed it —
    # because it is a property of the mission's own configuration and it is
    # read on BOTH sides of the containment rail: composition stamps it, and
    # a scale-in refuses to terminate a victim that does not carry it. Two
    # private copies of that derivation would let the two sides disagree about
    # what this mission owns, which is precisely the containment failure the
    # marker exists to prevent.
    def provenance_name_prefix
      cfg = configuration
      return nil unless cfg.is_a?(Hash)

      explicit = cfg["name_prefix"].presence
      return explicit if explicit

      run_id = cfg["dryrun_run_id"].presence
      run_id ? "dryrun-#{run_id}" : nil
    end

    # M4 Enterprise Polish — second-signature gate.
    #
    # Returns true when the mission is sitting at the `handoff` phase AND
    # the account's active plan has `features["second_signature_required"]`
    # set to true. Business+ tiers opt in via the plan seed. Free/Pro tiers
    # return false here so the existing single-approval handoff flow is
    # preserved verbatim.
    #
    # Defensive against missing chain links — if any of account /
    # active_subscription / plan / features is nil or non-hash, returns
    # false (fail-open to existing behavior, never harder than configured).
    def requires_second_signature?
      return false unless current_phase == "handoff"

      features = account&.try(:active_subscription)&.try(:plan)&.try(:features)
      features.is_a?(Hash) && features["second_signature_required"] == true
    end

    # Distinct count of approved approvers at the given gate. Used by the
    # second-signature gate to determine whether the threshold (>= 2 distinct
    # users) has been met. Same user approving twice counts once.
    def distinct_approver_count(gate)
      approvals.approved.where(gate: gate).distinct.pluck(:user_id).compact.length
    end

    # Approval-unification cascade target. Ai::ApprovalRequest#notify_source_of_decision
    # invokes this when a gateway-routed mission gate resolves (see
    # Ai::Approvals::Gateway). Advances the mission on approval, rolls it back on
    # rejection/expiry — but only while the mission is still parked at the gate
    # the request was opened for, which guards against stale or duplicate
    # cascades after the mission has already moved on.
    #
    # Note: request_data["action_type"] holds the GATE name (e.g.
    # "feature_selection") while current_phase holds the PHASE name (e.g.
    # "awaiting_feature_approval"), so we compare via the canonical
    # phase→gate mapping rather than equating them directly.
    def on_approval_decision(request)
      gate = request.request_data["action_type"].presence
      return unless awaiting_approval?
      return unless gate.blank? ||
                    gate == Ai::MissionApproval.gate_for_phase(current_phase, mission: self)

      orchestrator = Ai::Missions::OrchestratorService.new(mission: self)
      case request.status
      when "approved"
        orchestrator.advance!(result: { approval_request_id: request.id })
      when "rejected", "expired"
        orchestrator.reject_gate!(comment: request.decisions.order(:created_at).last&.comments)
      end
    end

    # ---- canonical land source seam (Ai::Land, flag-gated default OFF) -----
    # These let a Mission act as a polymorphic land source for the unified
    # Ai::Land::LandService, mirroring the campaign hooks. They are only reached
    # when Ai::Land::Feature.mission_landing_enabled? is on (default false), so
    # by default a mission's merging phase keeps dispatching AiMissionMergeJob
    # and none of this runs.

    # Surface a land issue to the mission's creator (best-effort; never raises).
    def land_park_notify!(reason:, land:)
      Notification.create_for_user(
        created_by,
        type: "mission_land_attention",
        title: "Mission land needs attention",
        message: "Mission **#{name}** land needs attention: #{reason}\n\n" \
                 "`#{land.source_branch}` → `#{land.target_branch}`",
        severity: "warning",
        category: "ai",
        action_url: "/app/ai/missions/#{id}",
        action_label: "Review Mission",
        metadata: { mission_id: id, campaign_land_id: land.id, reason: reason }
      )
    rescue StandardError => e
      Rails.logger.warn("[Ai::Mission] land_park_notify! failed (mission #{id}): #{e.message}")
    end

    # The land merged + post-merge CI passed: advance the mission out of the
    # merging phase to its terminal completion.
    def on_land_completed!(land)
      Ai::Missions::OrchestratorService.new(mission: self)
                                       .advance!(result: { campaign_land_id: land.id })
    end

    # The land's post-merge CI failed and the merge was reverted: roll the
    # mission back to the previewing gate so an operator can re-decide.
    def on_land_rolled_back!(_land)
      Ai::Missions::OrchestratorService.new(mission: self)
                                       .transition_to!("previewing", dispatch: false)
    end

    def phases_for_type
      if custom_phases.present?
        custom_phases.sort_by { |p| p["order"] || 0 }.map { |p| p["key"] }
      elsif mission_template.present?
        mission_template.phase_keys
      else
        []
      end
    end

    def phase_index
      phases_for_type.index(current_phase) || 0
    end

    def phase_progress
      total = phases_for_type.length
      return 0 if total.zero?
      ((phase_index.to_f / (total - 1)) * 100).round
    end

    def mission_summary
      {
        id: id,
        name: name,
        mission_type: mission_type,
        status: status,
        current_phase: current_phase,
        phase_progress: phase_progress,
        repository: repository&.full_name,
        team: team&.name,
        created_by: created_by&.name,
        started_at: started_at&.iso8601,
        completed_at: completed_at&.iso8601,
        duration_ms: duration_ms,
        mission_template_id: mission_template_id,
        phases: phases_for_type,
        approval_gate_phases: approval_gate_phases,
        created_at: created_at.iso8601
      }
    end

    def mission_details
      mission_summary.merge(
        repository_id: repository_id,
        team_id: team_id,
        description: description,
        objective: objective,
        phase_config: phase_config,
        analysis_result: analysis_result,
        feature_suggestions: feature_suggestions,
        selected_feature: selected_feature,
        prd_json: prd_json,
        test_result: test_result,
        review_result: review_result,
        phase_history: phase_history,
        configuration: configuration,
        branch_name: branch_name,
        base_branch: base_branch,
        pr_number: pr_number,
        pr_url: pr_url,
        deployed_port: deployed_port,
        deployed_url: deployed_url,
        error_message: error_message,
        error_details: error_details,
        conversation_id: conversation_id,
        ralph_loop_id: ralph_loop_id,
        risk_contract_id: risk_contract_id,
        review_state_id: review_state_id,
        custom_phases: custom_phases,
        approval_gate_phases: approval_gate_phases,
        approvals: approvals.order(created_at: :desc).map(&:approval_summary)
      )
    end

    def save_as_template!(name: nil, description: nil)
      template_phases = if custom_phases.present?
        custom_phases
      else
        phases_for_type.map.with_index do |phase_key, i|
          {
            "key" => phase_key,
            "label" => phase_key.humanize.titleize,
            "order" => i,
            "requires_approval" => approval_gate_phases.include?(phase_key)
          }
        end
      end

      Ai::MissionTemplate.create!(
        account: account,
        name: name || "Template from: #{self.name}",
        description: description || "Auto-generated from mission #{id}",
        template_type: "account",
        mission_type: mission_type,
        phases: template_phases,
        approval_gates: approval_gate_phases,
        rejection_mappings: build_rejection_mappings,
        default_configuration: configuration
      )
    end

    private

    def build_rejection_mappings
      if mission_template.present?
        mission_template.rejection_mappings || {}
      else
        {}
      end
    end

    # Tags the associated conversation as provisioning-typed so the chat
    # sidebar groups it accordingly. Idempotent: safe to call repeatedly,
    # only updates when the type isn't already 'provisioning'.
    def tag_conversation_as_provisioning
      conv = conversation
      return unless conv
      return if conv.conversation_type == "provisioning"
      conv.update_column(:conversation_type, "provisioning")
    end

    def post_milestone_to_conversation
      return unless conversation

      phase = current_phase
      previous_phase = saved_change_to_current_phase&.first

      # Resolve the previous approval gate message if we just left one
      resolve_approval_message(previous_phase) if previous_phase && approval_gate_phases.include?(previous_phase)

      message = if approval_gate_phases.include?(phase)
        "Mission **#{name}** requires **#{phase.humanize}** — review and approve to proceed"
      elsif phase == "completed"
        "Mission **#{name}** completed successfully!"
      else
        "Mission **#{name}** entered **#{phase.humanize}** phase (#{phase_progress}% complete)"
      end

      is_gate = approval_gate_phases.include?(phase)
      metadata = {
        "activity_type" => "mission_#{is_gate ? 'approval_required' : 'phase_changed'}",
        "mission_id" => id,
        "mission_name" => name,
        "phase" => phase,
        "phase_progress" => phase_progress
      }

      # Inline approval affordance — lets the operator approve/reject a
      # provisioning gate directly from the concierge chat (routed via
      # ConciergeService#handle_confirmed_action → OrchestratorService#handle_approval!).
      # Scoped to infrastructure missions so development-mission gates that
      # need richer input (feature selection, PRD edits) keep their modal UX.
      if is_gate && mission_type == "infrastructure"
        metadata.merge!(
          "concierge_action" => true,
          "action_type" => "approve_mission_gate",
          "action_params" => { "mission_id" => id, "gate" => phase, "decision" => "approved" },
          "actions" => [
            { "type" => "confirm", "label" => "Approve", "style" => "primary", "params" => { "decision" => "approved" } },
            { "type" => "reject", "label" => "Reject", "style" => "danger", "params" => { "decision" => "rejected" } }
          ],
          "action_context" => { "type" => "mission_approval", "action_type" => "approve_mission_gate", "status" => "pending" }
        )
      end

      conversation.add_system_message(message, content_metadata: metadata)

      # Push a real-time notification for approval gates
      if approval_gate_phases.include?(phase)
        notify_approval_required(phase.humanize)
      end
    rescue StandardError => e
      Rails.logger.warn("Failed to post mission milestone to conversation: #{e.message}")
    end

    def resolve_approval_message(gate_phase)
      pending_msg = conversation.messages
                                .where(role: "system")
                                .order(created_at: :desc)
                                .find { |m|
                                  m.content_metadata&.dig("activity_type") == "mission_approval_required" &&
                                    m.content_metadata&.dig("mission_id") == id &&
                                    m.content_metadata&.dig("phase") == gate_phase
                                }

      return unless pending_msg

      updated_metadata = pending_msg.content_metadata.deep_dup
      updated_metadata["resolved"] = true
      updated_metadata["resolved_at"] = Time.current.iso8601
      pending_msg.update!(content_metadata: updated_metadata)
    rescue StandardError => e
      Rails.logger.warn("Failed to resolve approval message: #{e.message}")
    end

    def notify_approval_required(gate_label)
      Notification.create_for_user(
        created_by,
        type: "ai_plan_review",
        title: "Mission awaiting #{gate_label}",
        message: "**\"#{name}\"** requires **#{gate_label}** before it can continue.\n\n" \
                 "Review and approve to allow the mission to proceed to the next phase.",
        severity: "warning",
        category: "ai",
        action_url: "/app/ai/missions/#{id}",
        action_label: "Review Mission",
        metadata: { mission_id: id, phase: current_phase }
      )
    rescue StandardError => e
      Rails.logger.warn("Failed to create approval notification: #{e.message}")
    end

    def set_defaults
      self.status ||= "draft"
      self.phase_config ||= {}
      self.analysis_result ||= {}
      self.feature_suggestions ||= []
      self.selected_feature ||= {}
      self.prd_json ||= {}
      self.test_result ||= {}
      self.review_result ||= {}
      self.phase_history ||= []
      self.configuration ||= {}
      self.metadata ||= {}
      self.error_details ||= {}
      self.base_branch = repository&.default_branch || base_branch if !base_branch_changed?
      assign_default_template if mission_template_id.blank? && custom_phases.blank?
    end

    def assign_default_template
      template = Ai::MissionTemplate
        .for_account(account_id)
        .active
        .defaults
        .by_type(mission_type)
        .first
      self.mission_template = template if template
    end

    def repository_required_for_development
      if mission_type == "development" && repository_id.blank?
        errors.add(:repository, "is required for development missions")
      end
    end

    def calculate_duration
      return unless started_at.present? && completed_at.present?

      self.duration_ms = ((completed_at - started_at) * 1000).to_i
    end

    def broadcast_status_update
      MissionChannel.broadcast_mission_event(id, "status_changed", {
        mission_id: id,
        status: status,
        current_phase: current_phase
      })
    rescue StandardError => e
      Rails.logger.warn("Failed to broadcast mission status update: #{e.message}")
    end

    def broadcast_phase_update
      MissionChannel.broadcast_mission_event(id, "phase_changed", {
        mission_id: id,
        status: status,
        current_phase: current_phase,
        phase_progress: phase_progress
      })
    rescue StandardError => e
      Rails.logger.warn("Failed to broadcast mission phase update: #{e.message}")
    end
  end
end
