# frozen_string_literal: true

module Ai
  # A question a Campaign cannot decide on its own (live credentials, irreversible external
  # side-effect, or pure business-policy value). The operator answers asynchronously; answering
  # can unblock the associated task. Replaces the markdown "morning questions" file.
  class ParkedQuestion < ApplicationRecord
    STATUSES = %w[open answered dismissed].freeze

    belongs_to :campaign, class_name: "Ai::Campaign", foreign_key: "campaign_id"
    belongs_to :ralph_task, class_name: "Ai::RalphTask", foreign_key: "ralph_task_id", optional: true
    belongs_to :answered_by, class_name: "User", foreign_key: "answered_by_id", optional: true

    validates :question, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :open, -> { where(status: "open") }
    scope :answered, -> { where(status: "answered") }

    def answer!(text, user: nil)
      return false unless status == "open"

      update!(status: "answered", answer: text, answered_by_id: user&.id, answered_at: Time.current)
      campaign.refresh_open_questions_count!
      true
    end

    def dismiss!
      update!(status: "dismissed").tap { campaign.refresh_open_questions_count! }
    end

    def summary
      {
        id: id, question: question, context: context, status: status, answer: answer,
        ralph_task_id: ralph_task_id, asked_at: created_at, answered_at: answered_at
      }
    end
  end
end
