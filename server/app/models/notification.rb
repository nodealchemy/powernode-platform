# frozen_string_literal: true

class Notification < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :user

  # Validations
  validates :notification_type, presence: true
  validates :title, presence: true
  validates :message, presence: true
  validates :severity, presence: true, inclusion: { in: %w[info success warning error critical] }

  # Scopes
  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :not_dismissed, -> { where(dismissed_at: nil) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :active, -> { not_dismissed.not_expired }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_category, ->(category) { where(category: category) }
  scope :by_type, ->(type) { where(notification_type: type) }

  # Notification types
  TYPES = %w[
    system_alert
    billing_reminder
    subscription_update
    security_alert
    feature_announcement
    usage_warning
    invitation_received
    team_update
    export_ready
    workflow_complete
    payment_failed
    account_update
    ai_plan_review
    ai_concierge_message
    agent_proposal
    agent_escalation
    agent_status_update
    agent_issue_detected
    agent_feedback_request
    agent_goal_achieved
    agent_improvement_applied
  ].freeze

  # Categories
  CATEGORIES = %w[
    general
    billing
    security
    account
    system
    workflow
    ai
  ].freeze

  # Callbacks
  after_create :broadcast_notification

  # Instance methods
  def read?
    read_at.present?
  end

  def dismissed?
    dismissed_at.present?
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end

  def mark_as_unread!
    update!(read_at: nil) if read?
  end

  def dismiss!
    update!(dismissed_at: Time.current) unless dismissed?
  end

  # Class methods
  class << self
    def create_for_user(user, type:, title:, message:, **options)
      create!(
        account: user.account,
        user: user,
        notification_type: type,
        title: title,
        message: message,
        **options
      )
    end

    def create_for_account(account, type:, title:, message:, **options)
      account.users.active.find_each do |user|
        create!(
          account: account,
          user: user,
          notification_type: type,
          title: title,
          message: message,
          **options
        )
      end
    end

    def create_system_notification(title:, message:, **options)
      Account.active.find_each do |account|
        create_for_account(account, type: "system_alert", title: title, message: message, **options)
      end
    end
  end

  private

  def broadcast_notification
    NotificationChannel.broadcast_to_account(account, {
      type: "new_notification",
      notification: as_json(
        only: [ :id, :notification_type, :title, :message, :severity, :action_url, :action_label, :icon, :category, :metadata, :created_at ],
        methods: [ :read? ]
      )
    })
  rescue StandardError => e
    Rails.logger.error "Failed to broadcast notification: #{e.message}"
  end
end
