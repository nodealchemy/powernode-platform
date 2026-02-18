# frozen_string_literal: true

module Ai
  class ComplianceAuditEntry < ApplicationRecord
    self.table_name = "ai_compliance_audit_entries"

    # Associations
    belongs_to :account
    belongs_to :user, optional: true

    # Validations
    validates :entry_id, presence: true, uniqueness: true
    validates :action_type, presence: true
    validates :resource_type, presence: true
    validates :outcome, presence: true, inclusion: { in: %w[success failure blocked warning] }
    validates :occurred_at, presence: true

    # Scopes
    scope :successful, -> { where(outcome: "success") }
    scope :failed, -> { where(outcome: "failure") }
    scope :blocked, -> { where(outcome: "blocked") }
    scope :warnings, -> { where(outcome: "warning") }
    scope :by_action, ->(type) { where(action_type: type) }
    scope :by_resource, ->(type) { where(resource_type: type) }
    scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
    scope :for_period, ->(start_date, end_date) { where(occurred_at: start_date..end_date) }
    scope :recent, -> { order(occurred_at: :desc) }
    scope :by_user, ->(user) { where(user: user) }

    # Callbacks
    before_validation :set_entry_id, on: :create
    before_validation :set_occurred_at, on: :create

    # Class methods
    def self.log!(account:, action_type:, resource_type:, resource_id: nil, outcome:, user: nil, description: nil, before_state: {}, after_state: {}, context: {}, ip_address: nil, user_agent: nil)
      create!(
        account: account,
        user: user,
        action_type: action_type,
        resource_type: resource_type,
        resource_id: resource_id,
        outcome: outcome,
        description: description,
        before_state: before_state,
        after_state: after_state,
        context: context,
        ip_address: ip_address,
        user_agent: user_agent,
        occurred_at: Time.current
      )
    end

    # Methods
    def successful?
      outcome == "success"
    end

    def failed?
      outcome == "failure"
    end

    def blocked?
      outcome == "blocked"
    end

    def has_state_change?
      before_state.present? || after_state.present?
    end

    def state_diff
      return {} unless has_state_change?

      changes = {}
      all_keys = (before_state.keys + after_state.keys).uniq

      all_keys.each do |key|
        before_val = before_state[key]
        after_val = after_state[key]
        next if before_val == after_val

        changes[key] = { before: before_val, after: after_val }
      end

      changes
    end

    private

    def set_entry_id
      self.entry_id ||= SecureRandom.uuid
    end

    def set_occurred_at
      self.occurred_at ||= Time.current
    end
  end
end
