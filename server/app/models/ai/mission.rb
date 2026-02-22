# frozen_string_literal: true

module Ai
  class Mission < ApplicationRecord
    self.table_name = "ai_missions"

    include Auditable

    # ==================== Constants ====================
    MISSION_TYPES = %w[development research operations].freeze

    DEVELOPMENT_PHASES = %w[
      analyzing awaiting_feature_approval planning awaiting_prd_approval
      executing testing reviewing awaiting_code_approval deploying previewing merging completed
    ].freeze
    RESEARCH_PHASES = %w[researching analyzing reporting completed].freeze
    OPERATIONS_PHASES = %w[configuring executing verifying completed].freeze

    STATUSES = %w[draft active paused completed failed cancelled].freeze
    TERMINAL_STATUSES = %w[completed failed cancelled].freeze
    APPROVAL_GATES = %w[awaiting_feature_approval awaiting_prd_approval awaiting_code_approval previewing].freeze

    # ==================== Associations ====================
    belongs_to :account
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id"
    belongs_to :repository, class_name: "Devops::GitRepository", foreign_key: "repository_id", optional: true
    belongs_to :team, class_name: "Ai::AgentTeam", foreign_key: "team_id", optional: true
    belongs_to :conversation, class_name: "Ai::Conversation", foreign_key: "conversation_id", optional: true
    belongs_to :risk_contract, class_name: "Ai::CodeFactory::RiskContract", foreign_key: "risk_contract_id", optional: true
    belongs_to :ralph_loop, class_name: "Ai::RalphLoop", foreign_key: "ralph_loop_id", optional: true
    belongs_to :review_state, class_name: "Ai::CodeFactory::ReviewState", foreign_key: "review_state_id", optional: true

    has_many :approvals, class_name: "Ai::MissionApproval", foreign_key: "mission_id", dependent: :destroy

    # ==================== Validations ====================
    validates :name, presence: true, length: { maximum: 255 }
    validates :mission_type, presence: true, inclusion: { in: MISSION_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :current_phase, inclusion: { in: ->(m) { m.phases_for_type } }, allow_nil: true
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
    scope :recent, -> { order(created_at: :desc) }
    scope :with_deployment, -> { where.not(deployed_port: nil) }

    # ==================== Callbacks ====================
    before_validation :set_defaults, on: :create
    before_save :calculate_duration, if: -> { completed_at_changed? && completed_at.present? }
    after_save :broadcast_status_update, if: :saved_change_to_status?
    after_save :broadcast_phase_update, if: :saved_change_to_current_phase?
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

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def awaiting_approval?
      APPROVAL_GATES.include?(current_phase)
    end

    def current_gate
      current_phase if awaiting_approval?
    end

    def phases_for_type
      case mission_type
      when "development" then DEVELOPMENT_PHASES
      when "research" then RESEARCH_PHASES
      when "operations" then OPERATIONS_PHASES
      else []
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
        approvals: approvals.order(created_at: :desc).map(&:approval_summary)
      )
    end

    private

    def post_milestone_to_conversation
      return unless conversation

      phase = current_phase
      previous_phase = saved_change_to_current_phase&.first

      # Resolve the previous approval gate message if we just left one
      resolve_approval_message(previous_phase) if previous_phase && Ai::Mission::APPROVAL_GATES.include?(previous_phase)

      gate_labels = {
        "awaiting_feature_approval" => "feature approval",
        "awaiting_prd_approval" => "PRD approval",
        "awaiting_code_approval" => "code review approval",
        "previewing" => "merge approval"
      }.freeze

      message = if Ai::Mission::APPROVAL_GATES.include?(phase)
        "Mission **#{name}** requires **#{gate_labels[phase] || phase.humanize}** — review and approve to proceed"
      elsif phase == "completed"
        "Mission **#{name}** completed successfully!"
      else
        "Mission **#{name}** entered **#{phase.humanize}** phase (#{phase_progress}% complete)"
      end

      conversation.add_system_message(message, content_metadata: {
        "activity_type" => "mission_#{Ai::Mission::APPROVAL_GATES.include?(phase) ? 'approval_required' : 'phase_changed'}",
        "mission_id" => id,
        "mission_name" => name,
        "phase" => phase,
        "phase_progress" => phase_progress
      })

      # Push a real-time notification for approval gates
      if Ai::Mission::APPROVAL_GATES.include?(phase)
        notify_approval_required(gate_labels[phase] || phase.humanize)
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
        message: "\"#{name}\" requires #{gate_label} before it can continue.",
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
