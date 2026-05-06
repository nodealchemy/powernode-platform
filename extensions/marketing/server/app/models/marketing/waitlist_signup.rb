# frozen_string_literal: true

module Marketing
  class WaitlistSignup < ApplicationRecord
    self.table_name = "marketing_waitlist_signups"

    belongs_to :email_subscriber,
      class_name: "Marketing::EmailSubscriber",
      foreign_key: "email_subscriber_id",
      optional: true
    belongs_to :converted_account,
      class_name: "Account",
      foreign_key: "converted_account_id",
      optional: true

    STATUSES = %w[pending confirmed unsubscribed].freeze

    validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :email, uniqueness: { case_sensitive: false }
    validates :status, presence: true, inclusion: { in: STATUSES }

    before_validation :downcase_email
    before_create :ensure_confirmation_token

    scope :pending, -> { where(status: "pending") }
    scope :confirmed, -> { where(status: "confirmed") }
    scope :unsubscribed, -> { where(status: "unsubscribed") }
    scope :converted, -> { where.not(converted_account_id: nil) }
    scope :by_source, ->(source) { where(source: source) }

    def confirm!
      update!(status: "confirmed", confirmed_at: Time.current, confirmation_token: nil)
    end

    def unsubscribe!
      update!(status: "unsubscribed", unsubscribed_at: Time.current)
    end

    def mark_converted!(account)
      update!(converted_account: account, converted_at: Time.current)
    end

    private

    def downcase_email
      self.email = email.to_s.strip.downcase
    end

    def ensure_confirmation_token
      self.confirmation_token ||= SecureRandom.urlsafe_base64(32)
    end
  end
end
