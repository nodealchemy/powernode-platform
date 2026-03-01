# frozen_string_literal: true

class CommunityAgentReport < ApplicationRecord
  # Concerns
  include Auditable

  # Constants
  REPORT_TYPES = %w[malicious spam inappropriate copyright other].freeze
  STATUSES = %w[pending investigating resolved dismissed].freeze

  # Associations
  belongs_to :community_agent
  belongs_to :reported_by_account, class_name: "Account"
  belongs_to :reported_by_user, class_name: "User"
  belongs_to :resolved_by, class_name: "User", optional: true

  # Validations
  validates :report_type, presence: true, inclusion: { in: REPORT_TYPES }
  validates :description, presence: true, length: { maximum: 5000 }
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :investigating, -> { where(status: "investigating") }
  scope :open, -> { where(status: %w[pending investigating]) }
  scope :closed, -> { where(status: %w[resolved dismissed]) }
  scope :by_type, ->(type) { where(report_type: type) }
  scope :recent, -> { order(created_at: :desc) }

  # Methods
  def pending?
    status == "pending"
  end

  def open?
    %w[pending investigating].include?(status)
  end

  def start_investigation!
    update!(status: "investigating")
  end

  def resolve!(user, notes: nil)
    update!(
      status: "resolved",
      resolved_by: user,
      resolved_at: Time.current,
      resolution_notes: notes
    )
  end

  def dismiss!(user, notes: nil)
    update!(
      status: "dismissed",
      resolved_by: user,
      resolved_at: Time.current,
      resolution_notes: notes
    )
  end

  def report_summary
    {
      id: id,
      community_agent_id: community_agent_id,
      report_type: report_type,
      status: status,
      created_at: created_at,
      resolved_at: resolved_at
    }
  end
end
