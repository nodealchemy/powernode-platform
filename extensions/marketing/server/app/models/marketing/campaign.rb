# frozen_string_literal: true

module Marketing
  class Campaign < ApplicationRecord
    include Auditable

    CAMPAIGN_TYPES = %w[email social chat sms multi_channel].freeze
    STATUSES = %w[draft scheduled active paused completed archived].freeze

    # Associations
    belongs_to :account
    belongs_to :creator, class_name: "User", foreign_key: "created_by_id"

    has_many :campaign_contents, class_name: "Marketing::CampaignContent", foreign_key: "campaign_id", dependent: :destroy
    has_many :campaign_metrics, class_name: "Marketing::CampaignMetric", foreign_key: "campaign_id", dependent: :destroy
    has_many :campaign_email_lists, class_name: "Marketing::CampaignEmailList", foreign_key: "campaign_id", dependent: :destroy
    has_many :email_lists, through: :campaign_email_lists
    has_many :calendar_entries, class_name: "Marketing::ContentCalendar", foreign_key: "campaign_id", dependent: :nullify

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :name, uniqueness: { scope: :account_id }
    validates :slug, presence: true, uniqueness: true
    validates :campaign_type, presence: true, inclusion: { in: CAMPAIGN_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :budget_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :spent_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    # JSON column defaults
    attribute :target_audience, :json, default: -> { {} }
    attribute :settings, :json, default: -> { {} }
    attribute :channels, :json, default: -> { [] }
    attribute :tags, :json, default: -> { [] }

    # Scopes
    scope :draft, -> { where(status: "draft") }
    scope :scheduled, -> { where(status: "scheduled") }
    scope :active, -> { where(status: "active") }
    scope :paused, -> { where(status: "paused") }
    scope :completed, -> { where(status: "completed") }
    scope :archived, -> { where(status: "archived") }
    scope :by_type, ->(type) { where(campaign_type: type) }
    scope :upcoming, -> { where("scheduled_at > ?", Time.current).order(scheduled_at: :asc) }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_validation :generate_slug, on: :create

    # Status transitions
    def schedule!(scheduled_time)
      raise "Campaign must be in draft status to schedule" unless status == "draft"

      update!(status: "scheduled", scheduled_at: scheduled_time)
    end

    def activate!
      raise "Campaign must be in draft or scheduled status to activate" unless %w[draft scheduled].include?(status)

      update!(status: "active", started_at: Time.current)
    end

    def pause!
      raise "Campaign must be active to pause" unless status == "active"

      update!(status: "paused", paused_at: Time.current)
    end

    def resume!
      raise "Campaign must be paused to resume" unless status == "paused"

      update!(status: "active", paused_at: nil)
    end

    def complete!
      raise "Campaign must be active to complete" unless status == "active"

      update!(status: "completed", completed_at: Time.current)
    end

    def archive!
      raise "Campaign must be completed or draft to archive" unless %w[completed draft].include?(status)

      update!(status: "archived")
    end

    # Helpers
    def budget_remaining_cents
      (budget_cents || 0) - (spent_cents || 0)
    end

    def over_budget?
      budget_cents.present? && budget_cents > 0 && spent_cents > budget_cents
    end

    def multi_channel?
      campaign_type == "multi_channel"
    end

    def campaign_summary
      {
        id: id,
        name: name,
        slug: slug,
        campaign_type: campaign_type,
        status: status,
        channels: channels,
        budget_cents: budget_cents,
        spent_cents: spent_cents,
        scheduled_at: scheduled_at,
        started_at: started_at,
        completed_at: completed_at,
        tags: tags,
        created_at: created_at
      }
    end

    def campaign_details
      campaign_summary.merge(
        target_audience: target_audience,
        settings: settings,
        paused_at: paused_at,
        creator: { id: creator.id, name: creator.name, email: creator.email },
        content_count: campaign_contents.count,
        email_list_count: email_lists.count,
        updated_at: updated_at
      )
    end

    private

    def generate_slug
      return if slug.present?

      base_slug = name&.parameterize
      self.slug = base_slug
      counter = 1
      while self.class.exists?(slug: self.slug)
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end
  end
end
