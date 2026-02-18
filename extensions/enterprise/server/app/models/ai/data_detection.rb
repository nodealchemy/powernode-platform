# frozen_string_literal: true

module Ai
  class DataDetection < ApplicationRecord
    self.table_name = "ai_data_detections"

    # Associations
    belongs_to :account
    belongs_to :classification, class_name: "Ai::DataClassification"

    # Validations
    validates :detection_id, presence: true, uniqueness: true
    validates :source_type, presence: true
    validates :source_id, presence: true
    validates :action_taken, presence: true, inclusion: { in: %w[logged masked blocked encrypted flagged] }

    # Scopes
    scope :by_source, ->(type, id) { where(source_type: type, source_id: id) }
    scope :by_action, ->(action) { where(action_taken: action) }
    scope :masked, -> { where(action_taken: "masked") }
    scope :blocked, -> { where(action_taken: "blocked") }
    scope :high_confidence, -> { where("confidence_score >= ?", 0.8) }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }

    # Callbacks
    before_validation :set_detection_id, on: :create

    # Methods
    def masked?
      action_taken == "masked"
    end

    def blocked?
      action_taken == "blocked"
    end

    def high_confidence?
      confidence_score.present? && confidence_score >= 0.8
    end

    def classification_level
      classification.classification_level
    end

    def sensitive?
      classification.sensitive?
    end

    private

    def set_detection_id
      self.detection_id ||= SecureRandom.uuid
    end
  end
end
