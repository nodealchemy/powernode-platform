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

    class << self
      # Find-or-strengthen the (account, name) chain: created fresh from
      # `defaults` + the requested single step on first use; on every later
      # call the EXISTING chain's step is reconciled against the request
      # rather than reused untouched.
      #
      # Before this, every one of Gateway#request! / AutonomyGate#resolve_chain
      # / ApprovalWorkflowService's find_or_create_chain used find_or_create_by!
      # with a block -- Rails only runs that block when INITIALIZING a new
      # record, so the first-ever call for a given (account, name) set
      # required_approvals/approvers, and every call after that silently
      # reused the existing row untouched. A caller asking for a second
      # signature (required_approvals: 2) got a single-approver chain back,
      # with no error and nothing logged.
      #
      # Strengthen-only, mirroring System::PackageModuleMaterializer's
      # ModuleDependency edges (a stored `recommends` is upgraded to
      # `requires`, never the reverse): the stored chain is raised to at
      # least the requested floor when it falls short, and left untouched
      # when it already meets or exceeds it. It is NEVER weakened by a later
      # call asking for less -- an approval gate that could be silently
      # loosened by whichever caller asks last is the inverse of this bug.
      def find_or_strengthen!(account:, name:, step_name:, approvers:, required_approvals:, defaults: {})
        chain = find_or_initialize_by(account: account, name: name)

        if chain.new_record?
          chain.assign_attributes(defaults)
          chain.steps = [ { "name" => step_name.to_s, "approvers" => approvers, "required_approvals" => required_approvals } ]
          chain.save!
          return chain
        end

        strengthen_step!(chain, approvers: approvers, required_approvals: required_approvals)
        chain
      end

      private

      def strengthen_step!(chain, approvers:, required_approvals:)
        current = (chain.steps || []).first || {}
        current_required = current["required_approvals"] || 1
        current_approvers = current["approvers"].presence || [ "*" ]

        approvers_ok = approvers_at_least_as_strong?(existing: current_approvers, requested: approvers)
        required_ok = current_required >= required_approvals

        if approvers_ok && required_ok
          log_discarded_approver_request!(chain, current_approvers: current_approvers, requested: approvers)
          return
        end

        new_required = [ current_required, required_approvals ].max
        new_approvers = approvers_ok ? current_approvers : approvers

        # The mismatch this method exists to close was SILENT — surface it,
        # the same discipline PackageModuleMaterializer's edge-strengthening
        # uses (a returned warning there; a log here, since this runs deep
        # under a request!/resolve_chain call with no warnings array to
        # thread back to the operator).
        Rails.logger.warn(
          "[Ai::ApprovalChain] chain '#{chain.name}' (account=#{chain.account_id}) was weaker than " \
          "requested — strengthening in place (never weakening): required_approvals " \
          "#{current_required} -> #{new_required}, approvers #{current_approvers.inspect} -> #{new_approvers.inspect}"
        )

        chain.steps = [ current.merge("required_approvals" => new_required, "approvers" => new_approvers) ]
        chain.save!
      end

      # `["*"]` is the unique universal/weakest approver set — the only
      # comparison safe to make without inventing a general ordering over
      # approver lists. Two different non-wildcard lists are never compared
      # against each other; the stored list wins unless it is exactly `["*"]`
      # while the request asks for something narrower.
      def approvers_at_least_as_strong?(existing:, requested:)
        return true unless existing == [ "*" ]
        requested == [ "*" ]
      end

      # strengthen_step! above logs when the STORED chain actually changes.
      # This covers the narrower residual: the stored chain does NOT change
      # (it is already at least as strong), but the caller's specific
      # approver request still gets overridden by a stored, unrelated,
      # equally non-wildcard set -- e.g. stored ["user-a"], requested
      # ["user-b"]. approvers_at_least_as_strong? is right to refuse
      # comparing two non-wildcard lists (there is no defensible ordering),
      # and the stored list should keep winning -- but "we kept yours out,
      # in favor of a different list" must not be silent, or this is the
      # original defect in a smaller box. A caller passing the default
      # (["*"], "anyone") isn't asking for anything specific, so that path
      # is exempt -- it is the ordinary chain-reuse case, not a discarded
      # request.
      def log_discarded_approver_request!(chain, current_approvers:, requested:)
        return if requested == current_approvers
        return if requested == [ "*" ]

        Rails.logger.info(
          "[Ai::ApprovalChain] chain '#{chain.name}' (account=#{chain.account_id}) kept its stored " \
          "approvers #{current_approvers.inspect} over a differing request #{requested.inspect} -- " \
          "neither set is comparably stronger, so the existing approvers win (never weakening); " \
          "the requested set was NOT applied."
        )
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
