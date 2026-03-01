# frozen_string_literal: true

module Ai
  class TrajectoryChapter < ApplicationRecord
    self.table_name = "ai_trajectory_chapters"

    # ==========================================
    # Constants
    # ==========================================
    CHAPTER_TYPES = %w[
      understanding investigation planning implementation
      testing reflection lessons_learned
    ].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :trajectory, class_name: "Ai::Trajectory", foreign_key: "trajectory_id"

    # ==========================================
    # Validations
    # ==========================================
    validates :chapter_number, presence: true,
              uniqueness: { scope: :trajectory_id }
    validates :title, presence: true
    validates :chapter_type, presence: true, inclusion: { in: CHAPTER_TYPES }
    validates :content, presence: true

    # ==========================================
    # Scopes
    # ==========================================
    scope :ordered, -> { order(:chapter_number) }
    scope :by_type, ->(type) { where(chapter_type: type) }

    # ==========================================
    # Public Methods
    # ==========================================

    def add_decision(decision:, rationale:, alternatives: [])
      self.key_decisions ||= []
      self.key_decisions << {
        "decision" => decision,
        "rationale" => rationale,
        "alternatives" => alternatives
      }
      save!
    end

    def add_artifact(type:, path:, action:)
      self.artifacts ||= []
      self.artifacts << {
        "type" => type,
        "path" => path,
        "action" => action
      }
      save!
    end
  end
end
