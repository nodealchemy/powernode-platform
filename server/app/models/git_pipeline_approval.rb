# frozen_string_literal: true

class GitPipelineApproval < ApplicationRecord
  # Constants
  STATUSES = %w[pending approved rejected expired cancelled].freeze

  # Associations
  belongs_to :git_pipeline
  belongs_to :account
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :responded_by, class_name: "User", optional: true

  has_one :git_repository, through: :git_pipeline

  # Validations
  validates :gate_name, presence: true, length: { maximum: 100 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :gate_name, uniqueness: { scope: :git_pipeline_id }

  validate :response_requires_responder, on: :update

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }
  scope :expired, -> { where(status: "expired") }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :active, -> { pending.where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expiring_soon, -> { pending.where("expires_at <= ?", 1.hour.from_now) }
  scope :for_pipeline, ->(pipeline_id) { where(git_pipeline_id: pipeline_id) }
  scope :for_environment, ->(env) { where(environment: env) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_create :set_default_expiry

  # Class Methods
  class << self
    def expire_stale!
      pending.where("expires_at <= ?", Time.current).find_each do |approval|
        approval.expire!
      end
    end

    def stats_for_account(account_id)
      approvals = where(account_id: account_id)
      {
        total: approvals.count,
        pending: approvals.pending.count,
        approved: approvals.approved.count,
        rejected: approvals.rejected.count,
        expired: approvals.expired.count
      }
    end
  end

  # Instance Methods
  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  def expired?
    status == "expired"
  end

  def cancelled?
    status == "cancelled"
  end

  def can_respond?
    pending? && !past_expiry?
  end

  def past_expiry?
    expires_at.present? && expires_at <= Time.current
  end

  def time_until_expiry
    return nil if expires_at.blank?
    return 0 if past_expiry?
    (expires_at - Time.current).to_i
  end

  def approve!(user, comment = nil)
    return false unless can_respond?

    update!(
      status: "approved",
      responded_by: user,
      response_comment: comment,
      responded_at: Time.current
    )
  end

  def reject!(user, comment = nil)
    return false unless can_respond?

    update!(
      status: "rejected",
      responded_by: user,
      response_comment: comment,
      responded_at: Time.current
    )
  end

  def expire!
    return false unless pending?

    update!(
      status: "expired",
      responded_at: Time.current
    )
  end

  def cancel!
    return false unless pending?

    update!(
      status: "cancelled",
      responded_at: Time.current
    )
  end

  def can_user_approve?(user)
    return false unless pending?
    return true if required_approvers.blank?

    # Check if user ID is in required approvers
    return true if required_approvers.include?(user.id)

    # Check if user has any of the required roles
    user_role_names = user.roles.pluck(:name)
    (required_approvers & user_role_names).any?
  end

  def response_time
    return nil if responded_at.blank?
    responded_at - created_at
  end

  private

  def set_default_expiry
    self.expires_at ||= 24.hours.from_now
  end

  def response_requires_responder
    if (status_changed? && %w[approved rejected].include?(status)) && responded_by.blank?
      errors.add(:responded_by, "is required when approving or rejecting")
    end
  end
end
