# frozen_string_literal: true

module Review
  class Notification < ApplicationRecord
    include AuditLogging

    # Associations
    belongs_to :app_review
    belongs_to :recipient, class_name: "Account"
    belongs_to :triggered_by, class_name: "Account", optional: true
    has_many :notification_deliveries, class_name: "Review::NotificationDelivery", foreign_key: :review_notification_id, dependent: :destroy

    # Validations
    validates :notification_type, presence: true, inclusion: {
      in: %w[new_review review_response review_flagged review_approved review_rejected
             review_milestone helpful_vote review_digest admin_alert],
      message: "must be a valid notification type"
    }
    validates :delivery_channels, presence: true
    validates :priority, inclusion: { in: %w[low normal high urgent] }
    validates :template_data, presence: true

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :sent, -> { where(status: "sent") }
    scope :failed, -> { where(status: "failed") }
    scope :by_type, ->(type) { where(notification_type: type) }
    scope :by_channel, ->(channel) { where("delivery_channels ? ?", channel) }
    scope :high_priority, -> { where(priority: [ "high", "urgent" ]) }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    after_create :schedule_delivery
    after_update :log_status_change, if: :saved_change_to_status?

    # Status methods
    def pending?
      status == "pending"
    end

    def sent?
      status == "sent"
    end

    def failed?
      status == "failed"
    end

    def processing?
      status == "processing"
    end

    # Priority methods
    def urgent?
      priority == "urgent"
    end

    def high_priority?
      %w[high urgent].include?(priority)
    end

    # Delivery methods
    def should_deliver_via?(channel)
      delivery_channels.include?(channel)
    end

    def mark_processing!
      update!(status: "processing", processed_at: Time.current)
    end

    def mark_sent!
      update!(status: "sent", sent_at: Time.current)
    end

    def mark_failed!(error_message = nil)
      update!(
        status: "failed",
        failed_at: Time.current,
        error_message: error_message
      )
    end

    def retry_delivery!
      return false if retry_count >= 3

      update!(
        status: "pending",
        retry_count: retry_count + 1,
        next_retry_at: calculate_next_retry_time
      )

      schedule_delivery
      true
    end

    # Content methods
    def notification_title
      template_data["title"] || default_title
    end

    def notification_body
      template_data["body"] || default_body
    end

    def notification_url
      template_data["url"] || default_url
    end

    def formatted_data
      base_data = {
        review_id: app_review.id,
        review_title: app_review.display_title,
        review_rating: app_review.rating,
        app_name: app_review.app.name,
        app_slug: app_review.app.slug,
        recipient_name: recipient.name
      }

      base_data.merge(template_data)
    end

    # Analytics methods
    def self.delivery_stats(days_back = 7)
      start_date = days_back.days.ago

      {
        total_sent: where("created_at >= ?", start_date).count,
        success_rate: calculate_success_rate(start_date),
        by_channel: group(:delivery_channels).count,
        by_type: where("created_at >= ?", start_date).group(:notification_type).count,
        avg_delivery_time: calculate_avg_delivery_time(start_date)
      }
    end

    def self.calculate_success_rate(start_date)
      total = where("created_at >= ?", start_date).count
      return 0.0 if total.zero?

      sent_count = where("created_at >= ? AND status = ?", start_date, "sent").count
      (sent_count.to_f / total * 100).round(2)
    end

    def self.calculate_avg_delivery_time(start_date)
      notifications = where("created_at >= ? AND sent_at IS NOT NULL", start_date)
      return 0.0 if notifications.empty?

      total_time = notifications.sum do |notification|
        (notification.sent_at - notification.created_at) / 1.minute
      end

      (total_time / notifications.count).round(2)
    end

    private

    def schedule_delivery
      # Schedule immediate delivery for urgent notifications
      if urgent?
        ReviewNotificationJob.perform_async(id)
      else
        # Schedule delivery based on priority
        delay = case priority
        when "high" then 1.minute
        when "normal" then 5.minutes
        else 15.minutes # low priority
        end

        ReviewNotificationJob.perform_in(delay, id)
      end
    end

    def calculate_next_retry_time
      # Exponential backoff: 1 min, 5 min, 30 min
      case retry_count
      when 0 then 1.minute.from_now
      when 1 then 5.minutes.from_now
      when 2 then 30.minutes.from_now
      else 2.hours.from_now
      end
    end

    def default_title
      case notification_type
      when "new_review"
        "New Review for #{app_review.app.name}"
      when "review_response"
        "Developer Responded to Your Review"
      when "review_flagged"
        "Review Flagged for Moderation"
      when "review_approved"
        "Your Review was Approved"
      when "review_rejected"
        "Review Requires Attention"
      when "review_milestone"
        "Review Milestone Reached!"
      when "helpful_vote"
        "Someone Found Your Review Helpful"
      when "review_digest"
        "Weekly Review Summary"
      when "admin_alert"
        "Admin Review Alert"
      else
        "Review Notification"
      end
    end

    def default_body
      case notification_type
      when "new_review"
        "#{app_review.reviewer_name} left a #{app_review.rating}-star review for your app."
      when "review_response"
        "The developer has responded to your review of #{app_review.app.name}."
      when "review_flagged"
        "A review for #{app_review.app.name} has been flagged and needs moderation."
      when "review_approved"
        "Your review of #{app_review.app.name} is now live."
      when "helpful_vote"
        "Your review of #{app_review.app.name} was marked as helpful."
      else
        "You have a new review notification."
      end
    end

    def default_url
      case notification_type
      when "new_review", "review_response", "helpful_vote"
        "/apps/#{app_review.app.slug}/reviews/#{app_review.id}"
      when "review_flagged", "admin_alert"
        "/admin/reviews/moderation/#{app_review.id}"
      when "review_approved", "review_rejected"
        "/apps/#{app_review.app.slug}/reviews"
      else
        "/reviews"
      end
    end

    def log_status_change
      Rails.logger.info "Review notification status changed: #{id} from #{status_before_last_save} to #{status}"
    end
  end
end

# Backward compatibility alias
ReviewNotification = Review::Notification unless defined?(ReviewNotification)
