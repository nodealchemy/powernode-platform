# frozen_string_literal: true

module Marketing
  class WaitlistSignup < ApplicationRecord
    self.table_name = "marketing_waitlist_signups"

    # Name of the auto-managed EmailList that confirmed signups are synced into.
    # Findable via Marketing::EmailList.find_by(name: WAITLIST_LIST_NAME) for
    # nurture-campaign workflows.
    WAITLIST_LIST_NAME = "Cloud Waitlist"

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

    # Transitions pending → confirmed and synchronously creates a
    # Marketing::EmailSubscriber on the auto-managed "Cloud Waitlist" list
    # so nurture campaigns can target the address. Sync errors are logged
    # but don't roll back the status transition — confirmation succeeds
    # even if the subscriber-list machinery is unhealthy.
    def confirm!
      update!(status: "confirmed", confirmed_at: Time.current, confirmation_token: nil)
      sync_to_email_subscriber!
      self
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

    # Idempotent: if email_subscriber_id is already set, returns immediately.
    # If no Account exists yet (fresh install), returns silently — the signup
    # row is still saved and confirmation still completes.
    def sync_to_email_subscriber!
      return if email_subscriber_id.present?

      account = Account.first
      return unless account

      list = Marketing::EmailList.find_or_create_by!(account: account, name: WAITLIST_LIST_NAME) do |l|
        l.list_type = "standard"
      end

      subscriber = Marketing::EmailSubscriber.find_or_create_by!(email_list: list, email: email) do |s|
        s.status = "subscribed"
        s.source = "waitlist"
        s.subscribed_at = Time.current
        s.confirmed_at = Time.current
      end

      update_column(:email_subscriber_id, subscriber.id)
    rescue StandardError => e
      Rails.logger.error("[Marketing::WaitlistSignup #{id}] sync_to_email_subscriber! failed: #{e.class} — #{e.message}")
    end
  end
end
