# frozen_string_literal: true

module Marketing
  class EmailList < ApplicationRecord
    LIST_TYPES = %w[standard dynamic segment].freeze

    # Associations
    belongs_to :account

    has_many :email_subscribers, class_name: "Marketing::EmailSubscriber", foreign_key: "email_list_id", dependent: :destroy
    has_many :campaign_email_lists, class_name: "Marketing::CampaignEmailList", foreign_key: "email_list_id", dependent: :destroy
    has_many :campaigns, through: :campaign_email_lists

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :slug, presence: true
    validates :slug, uniqueness: { scope: :account_id }
    validates :list_type, presence: true, inclusion: { in: LIST_TYPES }
    validates :subscriber_count, numericality: { greater_than_or_equal_to: 0 }

    # JSON column defaults
    attribute :dynamic_filter, :json, default: -> { {} }

    # Scopes
    scope :by_type, ->(type) { where(list_type: type) }
    scope :with_subscribers, -> { where("subscriber_count > 0") }

    # Callbacks
    before_validation :generate_slug, on: :create

    def update_subscriber_count!
      update_column(:subscriber_count, email_subscribers.subscribed.count)
    end

    def active_subscribers
      email_subscribers.subscribed
    end

    def list_summary
      {
        id: id,
        name: name,
        slug: slug,
        list_type: list_type,
        subscriber_count: subscriber_count,
        double_opt_in: double_opt_in,
        created_at: created_at
      }
    end

    def list_details
      list_summary.merge(
        dynamic_filter: dynamic_filter,
        welcome_email_subject: welcome_email_subject,
        welcome_email_body: welcome_email_body,
        campaign_count: campaigns.count,
        updated_at: updated_at
      )
    end

    private

    def generate_slug
      return if slug.present?

      base_slug = name&.parameterize
      self.slug = base_slug
      counter = 1
      while self.class.where(account_id: account_id, slug: self.slug).exists?
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end
  end
end
