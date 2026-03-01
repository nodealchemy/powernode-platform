# frozen_string_literal: true

module Marketing
  class EmailSubscriber < ApplicationRecord
    STATUSES = %w[pending subscribed unsubscribed bounced complained].freeze

    # Associations
    belongs_to :email_list, class_name: "Marketing::EmailList", foreign_key: "email_list_id"

    # Validations
    validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :email, uniqueness: { scope: :email_list_id, case_sensitive: false }
    validates :status, presence: true, inclusion: { in: STATUSES }

    # JSON column defaults
    attribute :custom_fields, :json, default: -> { {} }
    attribute :tags, :json, default: -> { [] }
    attribute :preferences, :json, default: -> { {} }

    # Scopes
    scope :subscribed, -> { where(status: "subscribed") }
    scope :pending, -> { where(status: "pending") }
    scope :unsubscribed, -> { where(status: "unsubscribed") }
    scope :bounced, -> { where(status: "bounced") }
    scope :active, -> { where(status: %w[pending subscribed]) }

    # Callbacks
    before_validation :normalize_email
    before_create :generate_confirmation_token
    after_save :update_list_count, if: :saved_change_to_status?

    def subscribe!
      update!(status: "subscribed", subscribed_at: Time.current, confirmed_at: Time.current)
    end

    def unsubscribe!
      update!(status: "unsubscribed", unsubscribed_at: Time.current)
    end

    def record_bounce!
      increment!(:bounce_count)
      update!(status: "bounced") if bounce_count >= 3
    end

    def record_complaint!
      update!(status: "complained")
    end

    def confirm!
      update!(status: "subscribed", confirmed_at: Time.current, subscribed_at: Time.current, confirmation_token: nil)
    end

    def full_name
      [first_name, last_name].compact.join(" ").presence
    end

    def subscriber_summary
      {
        id: id,
        email: email,
        first_name: first_name,
        last_name: last_name,
        status: status,
        source: source,
        tags: tags,
        subscribed_at: subscribed_at,
        created_at: created_at
      }
    end

    private

    def normalize_email
      self.email = email&.downcase&.strip
    end

    def generate_confirmation_token
      self.confirmation_token ||= SecureRandom.urlsafe_base64(32)
    end

    def update_list_count
      email_list.update_subscriber_count!
    end
  end
end
