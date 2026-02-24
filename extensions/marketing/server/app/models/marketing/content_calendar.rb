# frozen_string_literal: true

module Marketing
  class ContentCalendar < ApplicationRecord
    ENTRY_TYPES = %w[post email social event reminder].freeze
    STATUSES = %w[planned scheduled published cancelled].freeze

    # Associations
    belongs_to :account
    belongs_to :campaign, class_name: "Marketing::Campaign", foreign_key: "campaign_id", optional: true

    # Validations
    validates :title, presence: true, length: { maximum: 255 }
    validates :entry_type, presence: true, inclusion: { in: ENTRY_TYPES }
    validates :scheduled_date, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    # JSON column defaults
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :by_date_range, ->(start_date, end_date) { where(scheduled_date: start_date..end_date) }
    scope :upcoming, -> { where("scheduled_date >= ?", Date.current).order(scheduled_date: :asc, scheduled_time: :asc) }
    scope :planned, -> { where(status: "planned") }
    scope :published, -> { where(status: "published") }
    scope :by_type, ->(type) { where(entry_type: type) }

    def calendar_summary
      {
        id: id,
        title: title,
        entry_type: entry_type,
        scheduled_date: scheduled_date,
        scheduled_time: scheduled_time,
        all_day: all_day,
        color: color,
        status: status,
        campaign_id: campaign_id,
        campaign_name: campaign&.name
      }
    end
  end
end
