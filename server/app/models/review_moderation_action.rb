# frozen_string_literal: true

class ReviewModerationAction < ApplicationRecord
  include AuditLogging

  # Associations
  belongs_to :app_review
  belongs_to :moderator, class_name: "Account"

  # Validations
  validates :action_type, presence: true, inclusion: {
    in: %w[flag approve reject remove restore edit],
    message: "must be flag, approve, reject, remove, restore, or edit"
  }
  validates :previous_status, :new_status, length: { maximum: 30 }, allow_blank: true
  validates :reason, length: { maximum: 1000 }, allow_blank: true
  validates :notes, length: { maximum: 2000 }, allow_blank: true
  validates :confidence_score, length: { maximum: 10 }, allow_blank: true

  # Scopes
  scope :flagged, -> { where(action_type: "flag") }
  scope :approved, -> { where(action_type: "approve") }
  scope :rejected, -> { where(action_type: "reject") }
  scope :removed, -> { where(action_type: "remove") }
  scope :restored, -> { where(action_type: "restore") }
  scope :edited, -> { where(action_type: "edit") }
  scope :automated, -> { where(automated: true) }
  scope :manual, -> { where(automated: false) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_moderator, ->(moderator) { where(moderator: moderator) }

  # Callbacks
  after_create :log_moderation_action

  # Action type methods
  def flag_action?
    action_type == "flag"
  end

  def approve_action?
    action_type == "approve"
  end

  def reject_action?
    action_type == "reject"
  end

  def remove_action?
    action_type == "remove"
  end

  def restore_action?
    action_type == "restore"
  end

  def edit_action?
    action_type == "edit"
  end

  # Processing methods
  def automated?
    automated == true
  end

  def manual?
    !automated?
  end

  def has_confidence_score?
    confidence_score.present?
  end

  def high_confidence?
    return false unless has_confidence_score?

    score = confidence_score.to_f
    score >= 0.8
  end

  def low_confidence?
    return false unless has_confidence_score?

    score = confidence_score.to_f
    score < 0.6
  end

  # Display methods
  def action_type_display
    case action_type
    when "flag"
      "Flagged for Review"
    when "approve"
      "Approved"
    when "reject"
      "Rejected"
    when "remove"
      "Removed"
    when "restore"
      "Restored"
    when "edit"
      "Edited"
    else
      action_type.humanize
    end
  end

  def processing_type_display
    automated? ? "Automated" : "Manual"
  end

  def moderator_name
    moderator.name || "Moderator #{moderator.id[0..7]}"
  end

  def formatted_date
    created_at.strftime("%B %d, %Y at %I:%M %p")
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

  def status_change_summary
    return action_type_display unless previous_status.present? && new_status.present?

    "#{previous_status.humanize} → #{new_status.humanize}"
  end

  def confidence_percentage
    return nil unless has_confidence_score?

    (confidence_score.to_f * 100).round(1)
  end

  # Class methods for analytics
  def self.actions_by_type
    group(:action_type).count
  end

  def self.actions_by_moderator
    joins(:moderator)
      .group("accounts.name")
      .count
  end

  def self.automated_vs_manual
    group(:automated).count
  end

  def self.average_confidence_by_action
    where.not(confidence_score: [ nil, "" ])
      .group(:action_type)
      .average("confidence_score::float")
  end

  def self.recent_activity(days = 7)
    where("created_at >= ?", days.days.ago)
      .group_by_day(:created_at)
      .count
  end

  def self.efficiency_metrics
    total_actions = count
    automated_actions = automated.count

    return {} if total_actions.zero?

    {
      total_actions: total_actions,
      automated_percentage: (automated_actions.to_f / total_actions * 100).round(1),
      manual_percentage: ((total_actions - automated_actions).to_f / total_actions * 100).round(1),
      average_confidence: where.not(confidence_score: [ nil, "" ]).average("confidence_score::float")&.round(3) || 0,
      actions_per_day: total_actions.to_f / 30 # Last 30 days average
    }
  end

  private

  def log_moderation_action
    action_summary = "#{action_type_display} review #{app_review_id}"
    action_summary += " (#{processing_type_display.downcase})"
    action_summary += " by #{moderator_name}" unless automated?
    action_summary += " - #{reason}" if reason.present?
    action_summary += " (confidence: #{confidence_percentage}%)" if has_confidence_score?

    Rails.logger.info "Moderation action: #{action_summary}"
  end
end
