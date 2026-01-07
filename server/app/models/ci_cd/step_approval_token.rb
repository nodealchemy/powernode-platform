# frozen_string_literal: true

module CiCd
  # Secure token for email-based approval of pipeline steps
  # Allows users to approve or reject steps without authentication
  class StepApprovalToken < ApplicationRecord
    self.table_name = "ci_cd_step_approval_tokens"

    STATUSES = %w[pending approved rejected expired].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :step_execution, class_name: "CiCd::StepExecution"
    belongs_to :recipient_user, class_name: "User", optional: true
    belongs_to :responded_by, class_name: "User", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :token_digest, presence: true, uniqueness: true
    validates :recipient_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :expires_at, presence: true

    # ============================================
    # Scopes
    # ============================================
    scope :pending, -> { where(status: "pending") }
    scope :active, -> { pending.where("expires_at > ?", Time.current) }
    scope :expired_tokens, -> { pending.where("expires_at <= ?", Time.current) }
    scope :for_step_execution, ->(step_execution_id) { where(step_execution_id: step_execution_id) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :set_default_expiry, on: :create

    # ============================================
    # Class Methods
    # ============================================

    # Find token by raw token value (hashes and looks up)
    def self.find_by_token(raw_token)
      return nil if raw_token.blank?

      digest = generate_digest(raw_token)
      find_by(token_digest: digest)
    end

    # Generate a new token with raw value (returns [model, raw_token])
    def self.create_for_recipient(step_execution:, recipient_email:, recipient_user: nil, expires_in: 24.hours)
      raw_token = SecureRandom.urlsafe_base64(32)
      digest = generate_digest(raw_token)

      token = create!(
        step_execution: step_execution,
        token_digest: digest,
        recipient_email: recipient_email,
        recipient_user: recipient_user,
        expires_at: Time.current + expires_in
      )

      [token, raw_token]
    end

    def self.generate_digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end

    # ============================================
    # Instance Methods
    # ============================================

    def approve!(comment: nil, by_user: nil)
      return false unless can_respond?

      transaction do
        update!(
          status: "approved",
          response_comment: comment,
          responded_by: by_user,
          responded_at: Time.current
        )

        # Notify step execution of approval
        step_execution.handle_approval_response!(approved: true, comment: comment, by_user: by_user)
      end

      true
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Failed to approve token #{id}: #{e.message}")
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

        # Notify step execution of rejection
        step_execution.handle_approval_response!(approved: false, comment: comment, by_user: by_user)
      end

      true
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Failed to reject token #{id}: #{e.message}")
      false
    end

    def expire!
      return false unless pending?

      update!(status: "expired")
    end

    def can_respond?
      pending? && !expired?
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

    def expired?
      expires_at <= Time.current
    end

    def time_remaining
      return 0 if expired?

      (expires_at - Time.current).to_i
    end

    # Context for email template
    def email_context
      {
        token_id: id,
        recipient_email: recipient_email,
        step_name: step_execution.step_name,
        pipeline_name: step_execution.pipeline_run.pipeline.name,
        run_number: step_execution.pipeline_run.run_number,
        trigger_type: step_execution.pipeline_run.trigger_type,
        trigger_context: step_execution.pipeline_run.trigger_context,
        expires_at: expires_at,
        timeout_hours: approval_timeout_hours
      }
    end

    private

    def set_default_expiry
      return if expires_at.present?

      timeout_hours = step_execution&.pipeline_step&.approval_settings&.dig("timeout_hours") || 24
      self.expires_at = Time.current + timeout_hours.hours
    end

    def approval_timeout_hours
      step_execution&.pipeline_step&.approval_settings&.dig("timeout_hours") || 24
    end
  end
end
