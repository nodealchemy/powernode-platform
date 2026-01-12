# frozen_string_literal: true

class ReviewResponse < ApplicationRecord
  include AuditLogging

  # Associations
  belongs_to :app_review
  belongs_to :account
  belongs_to :approved_by, class_name: "Account", optional: true

  # Validations
  validates :content, presence: true, length: { minimum: 10, maximum: 1000 }
  validates :response_type, presence: true, inclusion: {
    in: %w[vendor_response customer_service clarification],
    message: "must be vendor_response, customer_service, or clarification"
  }
  validates :status, presence: true, inclusion: {
    in: %w[pending approved rejected],
    message: "must be pending, approved, or rejected"
  }

  # Scopes
  scope :approved, -> { where(status: "approved") }
  scope :pending, -> { where(status: "pending") }
  scope :rejected, -> { where(status: "rejected") }
  scope :vendor_responses, -> { where(response_type: "vendor_response") }
  scope :customer_service, -> { where(response_type: "customer_service") }
  scope :recent, -> { order(created_at: :desc) }
  scope :publicly_visible, -> { approved }

  # Callbacks
  after_create :log_response_created
  after_update :log_response_status_changed, if: :saved_change_to_status?

  # Status methods
  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  def publicly_visible?
    approved?
  end

  # Response type methods
  def vendor_response?
    response_type == "vendor_response"
  end

  def customer_service_response?
    response_type == "customer_service"
  end

  def clarification_response?
    response_type == "clarification"
  end

  # Moderation methods
  def approve!(moderator)
    update!(
      status: "approved",
      approved_at: Time.current,
      approved_by: moderator
    )
    log_response_approved(moderator)
  end

  def reject!(moderator, reason = nil)
    update!(status: "rejected")
    metadata["rejection_reason"] = reason if reason
    metadata["rejected_by"] = moderator.id
    metadata["rejected_at"] = Time.current.iso8601
    save!
    log_response_rejected(moderator, reason)
  end

  # Display methods
  def response_type_display
    case response_type
    when "vendor_response"
      "Developer Response"
    when "customer_service"
      "Customer Service"
    when "clarification"
      "Clarification"
    else
      response_type.humanize
    end
  end

  def author_name
    account.name || "User #{account.id[0..7]}"
  end

  def formatted_date
    created_at.strftime("%B %d, %Y")
  end

  def time_ago
    time_diff = Time.current - created_at

    case time_diff
    when 0..59
      "just now"
    when 60..3599
      "#{(time_diff / 60).round} minutes ago"
    when 3600..86399
      "#{(time_diff / 3600).round} hours ago"
    when 86400..2591999
      "#{(time_diff / 86400).round} days ago"
    else
      formatted_date
    end
  end

  # Content methods
  def content_preview(length = 100)
    return content if content.length <= length

    "#{content[0...length]}..."
  end

  def word_count
    content.split.length
  end

  private

  def log_response_created
    Rails.logger.info "Review response created: #{response_type} for review #{app_review_id} by account #{account_id}"
  end

  def log_response_status_changed
    Rails.logger.info "Review response status changed: #{id} from #{status_before_last_save} to #{status}"
  end

  def log_response_approved(moderator)
    Rails.logger.info "Review response approved: #{id} by moderator #{moderator.id}"
  end

  def log_response_rejected(moderator, reason)
    Rails.logger.info "Review response rejected: #{id} by moderator #{moderator.id} - Reason: #{reason}"
  end
end
