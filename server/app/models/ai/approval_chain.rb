# frozen_string_literal: true

module Ai
  class ApprovalChain < ApplicationRecord
    self.table_name = "ai_approval_chains"

    # Associations
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true

    has_many :approval_requests, class_name: "Ai::ApprovalRequest", dependent: :destroy

    APPROVER_TYPES = %w[user permission role].freeze

    # Validations
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :trigger_type, presence: true, inclusion: {
      in: %w[workflow_deploy agent_deploy high_cost sensitive_data model_change policy_override manual autonomy_action]
    }
    validates :status, presence: true, inclusion: { in: %w[active disabled] }
    validates :timeout_action, inclusion: { in: %w[approve reject escalate] }, allow_nil: true
    validate  :validate_steps_shape

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
        request_id: UUID7.generate,
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

    # Validates the canonical step shape:
    #   [
    #     {
    #       "name": "SRE Approval",
    #       "approvers": [
    #         "*",                                        # any active user
    #         "<user_uuid>",                              # legacy single-user reference
    #         { "type": "user",       "value": "<uuid>" },
    #         { "type": "permission", "value": "name" },
    #         { "type": "role",       "value": "name" }
    #       ],
    #       "required_approvals": 2,                     # default 1
    #       "allow_self_approval": false                 # default false
    #     }
    #   ]
    def validate_steps_shape
      return errors.add(:steps, "must be an array") unless steps.is_a?(Array)
      return errors.add(:steps, "must contain at least one step") if steps.empty?

      steps.each_with_index do |step, idx|
        prefix = "step #{idx}"
        unless step.is_a?(Hash)
          errors.add(:steps, "#{prefix} must be a hash")
          next
        end
        errors.add(:steps, "#{prefix} missing 'name'") if step["name"].blank?
        approvers = step["approvers"]
        if !approvers.is_a?(Array) || approvers.empty?
          errors.add(:steps, "#{prefix} must have a non-empty 'approvers' array")
        else
          approvers.each_with_index do |spec, sidx|
            validate_approver_spec(spec, "#{prefix} approver #{sidx}")
          end
        end
        required = step["required_approvals"]
        if required.present? && (!required.is_a?(Integer) || required < 1)
          errors.add(:steps, "#{prefix} 'required_approvals' must be a positive integer")
        end
      end
    end

    def validate_approver_spec(spec, prefix)
      case spec
      when "*", String then nil
      when Hash
        unless APPROVER_TYPES.include?(spec["type"])
          errors.add(:steps, "#{prefix} type must be one of #{APPROVER_TYPES.join(', ')}")
        end
        errors.add(:steps, "#{prefix} missing 'value'") if spec["value"].blank?
      else
        errors.add(:steps, "#{prefix} must be '*', user UUID string, or {type, value} hash")
      end
    end
  end
end
