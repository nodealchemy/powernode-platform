# frozen_string_literal: true

module Ai
  class WorkflowApprovalToken < ApplicationRecord
    STATUSES = %w[pending approved rejected expired].freeze

    # Associations
    belongs_to :node_execution, class_name: "Ai::WorkflowNodeExecution",
               foreign_key: "ai_workflow_node_execution_id"
    belongs_to :recipient_user, class_name: "User", optional: true
    belongs_to :responded_by, class_name: "User", optional: true

    # Validations
    validates :token_digest, presence: true, uniqueness: true
    validates :recipient_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :expires_at, presence: true

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :active, -> { pending.where("expires_at > ?", Time.current) }
    scope :expired_tokens, -> { pending.where("expires_at <= ?", Time.current) }
    scope :for_node_execution, ->(node_execution_id) { where(ai_workflow_node_execution_id: node_execution_id) }

    # Callbacks
    before_validation :set_default_expiry, on: :create

    # Class Methods
    def self.find_by_token(raw_token)
      return nil if raw_token.blank?

      digest = generate_digest(raw_token)
      find_by(token_digest: digest)
    end

    def self.create_for_recipient(node_execution:, recipient_email:, recipient_user: nil, expires_in: 24.hours)
      raw_token = SecureRandom.urlsafe_base64(32)
      digest = generate_digest(raw_token)

      token = create!(
        node_execution: node_execution,
        token_digest: digest,
        recipient_email: recipient_email,
        recipient_user: recipient_user,
        expires_at: Time.current + expires_in
      )

      [ token, raw_token ]
    end

    def self.generate_digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end

    # Instance Methods
    def approve!(comment: nil, by_user: nil)
      return false unless can_respond?

      transaction do
        update!(
          status: "approved",
          response_comment: comment,
          responded_by: by_user,
          responded_at: Time.current
        )

        node_execution.approve_execution!(
          by_user&.id,
          { "approved" => true, "comment" => comment, "reason" => comment }
        )
      end

      true
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Failed to approve AI workflow token #{id}: #{e.message}")
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

        node_execution.approve_execution!(
          by_user&.id,
          { "approved" => false, "comment" => comment, "reason" => comment }
        )
      end

      true
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Failed to reject AI workflow token #{id}: #{e.message}")
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

    def email_context
      workflow_run = node_execution.workflow_run
      workflow = workflow_run.workflow
      node = node_execution.node

      {
        token_id: id,
        recipient_email: recipient_email,
        node_name: node&.name || "Human Approval",
        workflow_name: workflow.name,
        run_id: workflow_run.run_id,
        trigger_type: workflow_run.trigger_type,
        approval_message: node_execution.metadata["approval_message"],
        expires_at: expires_at,
        timeout_hours: approval_timeout_hours
      }
    end

    private

    def set_default_expiry
      return if expires_at.present?

      timeout_hours = node_execution&.node&.configuration&.dig("approval_timeout_hours") || 24
      self.expires_at = Time.current + timeout_hours.hours
    end

    def approval_timeout_hours
      node_execution&.node&.configuration&.dig("approval_timeout_hours") || 24
    end
  end
end
