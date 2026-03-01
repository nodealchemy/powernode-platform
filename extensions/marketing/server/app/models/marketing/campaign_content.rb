# frozen_string_literal: true

module Marketing
  class CampaignContent < ApplicationRecord
    CHANNELS = %w[email twitter linkedin facebook instagram sms chat].freeze
    STATUSES = %w[draft approved rejected].freeze

    # Associations
    belongs_to :campaign, class_name: "Marketing::Campaign", foreign_key: "campaign_id"
    belongs_to :approved_by, class_name: "User", optional: true

    # Validations
    validates :channel, presence: true, inclusion: { in: CHANNELS }
    validates :variant_name, presence: true
    validates :variant_name, uniqueness: { scope: [:campaign_id, :channel] }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :body, presence: true

    # JSON column defaults
    attribute :media_urls, :json, default: -> { [] }
    attribute :platform_specific, :json, default: -> { {} }

    # Scopes
    scope :draft, -> { where(status: "draft") }
    scope :approved, -> { where(status: "approved") }
    scope :rejected, -> { where(status: "rejected") }
    scope :by_channel, ->(channel) { where(channel: channel) }
    scope :ai_generated, -> { where(ai_generated: true) }

    # Status transitions
    def approve!(user)
      update!(status: "approved", approved_by: user, approved_at: Time.current)
    end

    def reject!
      update!(status: "rejected")
    end

    def content_summary
      {
        id: id,
        channel: channel,
        variant_name: variant_name,
        subject: subject,
        preview_text: preview_text,
        ai_generated: ai_generated,
        status: status,
        approved_at: approved_at,
        created_at: created_at
      }
    end

    def content_details
      content_summary.merge(
        body: body,
        media_urls: media_urls,
        cta_text: cta_text,
        cta_url: cta_url,
        platform_specific: platform_specific,
        approved_by: approved_by&.name,
        campaign_id: campaign_id,
        updated_at: updated_at
      )
    end
  end
end
