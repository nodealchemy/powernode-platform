# frozen_string_literal: true

module Ai
  class ApprovalChain < ApplicationRecord
    self.table_name = "ai_approval_chains"

    # Associations
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true

    has_many :approval_requests, class_name: "Ai::ApprovalRequest", dependent: :destroy

    # Validations
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :trigger_type, presence: true, inclusion: {
      in: %w[workflow_deploy agent_deploy high_cost sensitive_data model_change policy_override manual autonomy_action]
    }
    validates :status, presence: true, inclusion: { in: %w[active disabled] }
    validates :timeout_action, inclusion: { in: %w[approve reject escalate] }, allow_nil: true

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :by_trigger, ->(type) { where(trigger_type: type) }

    # Methods
    def active?
      status == "active"
    end

    def sequential?
      is_sequential
    end

    def step_count
      steps&.length || 0
    end

    def create_request!(source_type:, source_id:, description:, request_data: {}, requested_by: nil)
      approval_requests.create!(
        account: account,
        request_id: SecureRandom.uuid,
        status: "pending",
        source_type: source_type,
        source_id: source_id,
        description: description,
        request_data: request_data,
        requested_by: requested_by,
        step_statuses: initialize_step_statuses,
        current_step: 0,
        expires_at: timeout_hours.present? ? timeout_hours.hours.from_now : nil
      )
    end

    def matches_trigger?(context)
      return true if trigger_conditions.blank?

      trigger_conditions.all? do |key, expected|
        actual = context[key.to_sym] || context[key.to_s]
        actual == expected
      end
    end

    private

    def initialize_step_statuses
      (steps || []).map.with_index do |step, index|
        {
          step_number: index,
          step_name: step["name"],
          approvers: step["approvers"],
          status: "pending",
          required_approvals: step["required_approvals"] || 1,
          current_approvals: 0
        }
      end
    end
  end
end
