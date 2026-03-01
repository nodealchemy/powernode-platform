# frozen_string_literal: true

# Approvable concern for models that manage approval tokens
# Provides common approval lifecycle: token generation, lookup, approve/reject/expire flows.
#
# Required columns:
#   - token_digest (string, uniquely indexed)
#   - recipient_email (string)
#   - status (string, default: "pending")
#   - expires_at (datetime)
#   - response_comment (text, optional)
#   - responded_at (datetime, optional)
#
# Required associations (defined in including model):
#   - belongs_to :recipient_user (optional)
#   - belongs_to :responded_by (optional)
#
# Including model must define:
#   - #approval_target — the associated record to notify on approve/reject
#   - #notify_approval!(comment, by_user) — called when approved
#   - #notify_rejection!(comment, by_user) — called when rejected
#   - #default_timeout_hours — hours until token expires (default: 24)
#
module Approvable
  extend ActiveSupport::Concern

  APPROVAL_STATUSES = %w[pending approved rejected expired].freeze

  included do
    validates :token_digest, presence: true, uniqueness: true
    validates :recipient_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :status, presence: true, inclusion: { in: APPROVAL_STATUSES }
    validates :expires_at, presence: true

    scope :pending, -> { where(status: "pending") }
    scope :active, -> { pending.where("expires_at > ?", Time.current) }
    scope :expired_tokens, -> { pending.where("expires_at <= ?", Time.current) }

    before_validation :set_default_expiry, on: :create
  end

  class_methods do
    def find_by_token(raw_token)
      return nil if raw_token.blank?

      digest = generate_digest(raw_token)
      find_by(token_digest: digest)
    end

    def generate_digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end

    def generate_raw_token
      SecureRandom.urlsafe_base64(32)
    end
  end

  def approve!(comment: nil, by_user: nil)
    return false unless can_respond?

    transaction do
      update!(
        status: "approved",
        response_comment: comment,
        responded_by: by_user,
        responded_at: Time.current
      )
      notify_approval!(comment, by_user)
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Failed to approve #{self.class.name} #{id}: #{e.message}")
    false
  end

  def reject!(comment: nil, by_user: nil)
    return false unless can_respond?

    transaction do
      update!(
        status: "rejected",
        response_comment: comment,
        responded_by: by_user,
        responded_at: Time.current
      )
      notify_rejection!(comment, by_user)
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Failed to reject #{self.class.name} #{id}: #{e.message}")
    false
  end

  def expire!
    return false unless pending?

    update!(status: "expired")
  end

  def can_respond?
    pending? && !token_expired?
  end

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  def token_expired?
    expires_at <= Time.current
  end

  def time_remaining
    return 0 if token_expired?

    (expires_at - Time.current).to_i
  end

  private

  def set_default_expiry
    return if expires_at.present?

    self.expires_at = Time.current + default_timeout_hours.hours
  end

  def default_timeout_hours
    24
  end
end
