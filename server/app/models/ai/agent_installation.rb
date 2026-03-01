# frozen_string_literal: true

module Ai
  class AgentInstallation < ApplicationRecord
    self.table_name = "ai_agent_installations"

    # Associations
    belongs_to :account
    belongs_to :agent_template, class_name: "Ai::AgentTemplate", foreign_key: "agent_template_id"
    belongs_to :installed_agent, class_name: "Ai::Agent", foreign_key: "installed_agent_id", optional: true
    belongs_to :installed_by, class_name: "User", foreign_key: "installed_by_id", optional: true

    has_one :review, class_name: "Ai::AgentReview", foreign_key: :installation_id

    # Validations
    validates :status, presence: true, inclusion: { in: %w[active paused expired cancelled pending_update] }
    validates :license_type, presence: true, inclusion: { in: %w[standard enterprise trial] }
    validates :account_id, uniqueness: { scope: :agent_template_id, message: "already has this template installed" }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :expired, -> { where(status: "expired") }
    scope :with_valid_license, -> { where("license_expires_at IS NULL OR license_expires_at > ?", Time.current) }

    # Callbacks
    after_create :update_template_counters
    after_destroy :decrement_template_counters

    # Methods
    def active?
      status == "active"
    end

    def expired?
      license_expires_at.present? && license_expires_at < Time.current
    end

    def valid_license?
      license_expires_at.nil? || license_expires_at > Time.current
    end

    def check_expiration!
      return unless expired? && status == "active"

      update!(status: "expired")
    end

    def record_execution(cost = 0)
      increment!(:executions_count)
      increment!(:total_cost_usd, cost) if cost > 0
      update!(last_used_at: Time.current)
    end

    def pause!
      update!(status: "paused") if active?
    end

    def resume!
      return false unless valid_license?

      update!(status: "active") if status == "paused"
    end

    def cancel!
      update!(status: "cancelled")
      decrement_template_counters
    end

    private

    def update_template_counters
      agent_template.increment_installations!
    end

    def decrement_template_counters
      agent_template.decrement_active_installations!
    end
  end
end
