# frozen_string_literal: true

module Ai
  class ApprovalRequest < ApplicationRecord
    self.table_name = "ai_approval_requests"

    # Associations
    belongs_to :account
    belongs_to :approval_chain, class_name: "Ai::ApprovalChain"
    belongs_to :requested_by, class_name: "User", optional: true

    has_many :decisions, class_name: "Ai::ApprovalDecision", dependent: :destroy

    # Validations
    validates :request_id, presence: true, uniqueness: true
    validates :status, presence: true, inclusion: { in: %w[pending approved rejected expired cancelled] }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :approved, -> { where(status: "approved") }
    scope :rejected, -> { where(status: "rejected") }
    scope :expired, -> { where(status: "expired") }
    scope :active, -> { pending.where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :for_source, ->(type, id) { where(source_type: type, source_id: id) }

    # Callbacks
    before_validation :set_request_id, on: :create

    # Methods
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
      expires_at.present? && expires_at < Time.current
    end

    def current_step_info
      step_statuses[current_step] if step_statuses.present?
    end

    def can_approve?(user)
      return false unless pending?
      return false if expired?

      step_info = current_step_info
      return false unless step_info

      approvers = step_info["approvers"] || []
      approvers.include?(user.id.to_s) || approvers.include?("*")
    end

    def record_decision!(approver:, decision:, comments: nil, conditions: {})
      return false unless can_approve?(approver)

      decisions.create!(
        approver: approver,
        step_number: current_step,
        decision: decision,
        comments: comments,
        conditions: conditions
      )

      process_decision(decision)
    end

    def check_expiration!
      return unless pending? && expired?

      case approval_chain.timeout_action
      when "approve"
        approve!
      when "reject"
        reject!
      when "escalate"
        escalate!
      else
        update!(status: "expired")
      end
    end

    private

    def set_request_id
      self.request_id ||= SecureRandom.uuid
    end

    def process_decision(decision)
      step_info = step_statuses[current_step]

      case decision
      when "approved"
        step_info["current_approvals"] += 1
        step_info["status"] = "approved" if step_info["current_approvals"] >= step_info["required_approvals"]

        if step_info["status"] == "approved"
          if current_step >= step_statuses.length - 1
            approve!
          else
            advance_to_next_step!
          end
        end
      when "rejected"
        step_info["status"] = "rejected"
        reject!
      when "delegated"
        # Delegation logic - could reassign to another approver
        step_info["status"] = "delegated"
      end

      update!(step_statuses: step_statuses)
    end

    def advance_to_next_step!
      update!(current_step: current_step + 1)
    end

    def approve!
      update!(status: "approved", completed_at: Time.current)
      approval_chain.increment!(:usage_count)
    end

    def reject!
      update!(status: "rejected", completed_at: Time.current)
    end

    def escalate!
      # Could notify higher-level approvers or auto-approve
      update!(status: "expired")
    end
  end
end
