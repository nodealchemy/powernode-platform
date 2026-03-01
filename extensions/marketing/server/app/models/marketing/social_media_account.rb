# frozen_string_literal: true

module Marketing
  class SocialMediaAccount < ApplicationRecord
    PLATFORMS = %w[twitter linkedin facebook instagram].freeze
    STATUSES = %w[connected disconnected expired error].freeze

    # Associations
    belongs_to :account
    belongs_to :connected_by, class_name: "User", optional: true

    # Validations
    validates :platform, presence: true, inclusion: { in: PLATFORMS }
    validates :platform_account_id, presence: true
    validates :platform_account_id, uniqueness: { scope: [:account_id, :platform] }
    validates :status, presence: true, inclusion: { in: STATUSES }

    # Scopes
    scope :connected, -> { where(status: "connected") }
    scope :by_platform, ->(platform) { where(platform: platform) }
    scope :expiring_soon, -> { where("token_expires_at < ?", 7.days.from_now).where("token_expires_at > ?", Time.current) }
    scope :expired, -> { where("token_expires_at < ?", Time.current) }

    def connected?
      status == "connected"
    end

    def token_expired?
      token_expires_at.present? && token_expires_at < Time.current
    end

    def mark_expired!
      update!(status: "expired")
    end

    def mark_error!
      update!(status: "error")
    end

    def mark_connected!
      update!(status: "connected")
    end

    def account_summary
      {
        id: id,
        platform: platform,
        platform_username: platform_username,
        status: status,
        post_count: post_count,
        token_expires_at: token_expires_at,
        created_at: created_at
      }
    end

    def account_details
      account_summary.merge(
        platform_account_id: platform_account_id,
        scopes: scopes,
        rate_limit_remaining: rate_limit_remaining,
        rate_limit_reset_at: rate_limit_reset_at,
        connected_by: connected_by&.name,
        updated_at: updated_at
      )
    end
  end
end
