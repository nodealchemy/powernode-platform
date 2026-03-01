# frozen_string_literal: true

module Ai
  class AgentGoal < ApplicationRecord
    self.table_name = "ai_agent_goals"

    MAX_ACTIVE_GOALS = 5
    MAX_DEPTH = 3
    STALE_DAYS = 30

    GOAL_TYPES = %w[maintenance improvement creation monitoring feature_suggestion reaction].freeze
    STATUSES = %w[pending active paused achieved abandoned failed].freeze
    TERMINAL_STATUSES = %w[achieved abandoned failed].freeze

    # Associations
    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"
    belongs_to :parent_goal, class_name: "Ai::AgentGoal", optional: true
    belongs_to :created_by, polymorphic: true, optional: true

    has_many :sub_goals, class_name: "Ai::AgentGoal", foreign_key: "parent_goal_id", dependent: :destroy
    has_many :observations, class_name: "Ai::AgentObservation", foreign_key: "goal_id", dependent: :nullify

    # Validations
    validates :title, presence: true, length: { maximum: 255 }
    validates :goal_type, presence: true, inclusion: { in: GOAL_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :priority, presence: true, inclusion: { in: 1..5 }
    validates :progress, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

    validate :max_active_goals, on: :create
    validate :max_nesting_depth, on: :create

    # JSON columns
    attribute :success_criteria, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :active, -> { where(status: %w[pending active paused]) }
    scope :actionable, -> { where(status: %w[pending active]) }
    scope :terminal, -> { where(status: TERMINAL_STATUSES) }
    scope :by_priority, -> { order(priority: :asc, created_at: :asc) }
    scope :top_level, -> { where(parent_goal_id: nil) }
    scope :stale, -> { active.where("updated_at < ?", STALE_DAYS.days.ago) }
    scope :for_agent, ->(agent_id) { where(ai_agent_id: agent_id) }

    # Instance methods
    def active?
      %w[pending active paused].include?(status)
    end

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def root_goal
      parent_goal_id.nil? ? self : parent_goal.root_goal
    end

    def depth
      parent_goal_id.nil? ? 0 : 1 + parent_goal.depth
    end

    def update_progress!(value)
      update!(progress: value.clamp(0.0, 1.0))
      achieve! if progress >= 1.0
    end

    def achieve!
      update!(status: "achieved", progress: 1.0)
    end

    def abandon!(reason = nil)
      update!(status: "abandoned", metadata: metadata.merge("abandon_reason" => reason))
    end

    def fail!(reason = nil)
      update!(status: "failed", metadata: metadata.merge("failure_reason" => reason))
    end

    def activate!
      update!(status: "active") if status == "pending"
    end

    def pause!
      update!(status: "paused") if status == "active"
    end

    private

    def max_active_goals
      return unless agent

      active_count = self.class.for_agent(ai_agent_id).active.count
      if active_count >= MAX_ACTIVE_GOALS
        errors.add(:base, "Agent already has #{MAX_ACTIVE_GOALS} active goals")
      end
    end

    def max_nesting_depth
      return unless parent_goal_id

      if depth >= MAX_DEPTH
        errors.add(:parent_goal_id, "exceeds maximum nesting depth of #{MAX_DEPTH}")
      end
    end
  end
end
