# frozen_string_literal: true

module Ai
  class Trajectory < ApplicationRecord
    self.table_name = "ai_trajectories"

    # ==========================================
    # Constants
    # ==========================================
    STATUSES = %w[building completed archived].freeze
    TRAJECTORY_TYPES = %w[task_completion workflow_run investigation implementation self_challenge].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :ai_agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true
    has_many :chapters, class_name: "Ai::TrajectoryChapter",
             foreign_key: :trajectory_id, dependent: :destroy

    # ==========================================
    # Validations
    # ==========================================
    validates :trajectory_id, presence: true, uniqueness: true
    validates :title, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :trajectory_type, presence: true, inclusion: { in: TRAJECTORY_TYPES }

    # ==========================================
    # Scopes
    # ==========================================
    scope :building, -> { where(status: "building") }
    scope :completed, -> { where(status: "completed") }
    scope :archived, -> { where(status: "archived") }
    scope :by_type, ->(type) { where(trajectory_type: type) }
    scope :for_agent, ->(agent_id) { where(ai_agent_id: agent_id) }
    scope :recent, -> { order(created_at: :desc) }
    scope :by_quality, -> { order(quality_score: :desc) }
    scope :with_tags, ->(tags) { where("tags ?| array[:tags]", tags: Array(tags)) }

    # ==========================================
    # Callbacks
    # ==========================================
    before_validation :generate_trajectory_id, on: :create
    after_save :update_chapter_count

    # ==========================================
    # Public Methods
    # ==========================================

    def complete!(quality_score: nil, outcome_summary: {})
      update!(
        status: "completed",
        quality_score: quality_score,
        outcome_summary: outcome_summary,
        chapter_count: chapters.count
      )
    end

    def archive!
      update!(status: "archived")
    end

    def record_access!
      increment!(:access_count)
    end

    def add_chapter(attrs)
      next_number = (chapters.maximum(:chapter_number) || 0) + 1
      chapters.create!(attrs.merge(chapter_number: next_number))
    end

    private

    def generate_trajectory_id
      return if trajectory_id.present?

      self.trajectory_id = "traj_#{SecureRandom.hex(12)}"
    end

    def update_chapter_count
      return unless saved_change_to_status? && status == "completed"

      update_column(:chapter_count, chapters.count) if chapter_count != chapters.count
    end
  end
end
