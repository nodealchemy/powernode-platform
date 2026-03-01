# frozen_string_literal: true

module Ai
  class KillSwitchEvent < ApplicationRecord
    self.table_name = "ai_kill_switch_events"

    # Associations
    belongs_to :account
    belongs_to :triggered_by, class_name: "User", foreign_key: "triggered_by_id"

    # Validations
    validates :event_type, presence: true, inclusion: { in: %w[halt resume] }
    validates :reason, presence: true

    # JSON column
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :halts, -> { where(event_type: "halt") }
    scope :resumes, -> { where(event_type: "resume") }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }

    # Instance methods
    def halt?
      event_type == "halt"
    end

    def resume?
      event_type == "resume"
    end

    def snapshot
      metadata&.dig("snapshot")
    end

    def impact
      metadata&.dig("impact")
    end

    def resume_mode
      metadata&.dig("resume_mode")
    end
  end
end
