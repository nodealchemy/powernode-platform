# frozen_string_literal: true

module Ai
  class Sandbox < ApplicationRecord
    self.table_name = "ai_sandboxes"

    # Associations
    belongs_to :account
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id", optional: true

    has_many :test_scenarios, class_name: "Ai::TestScenario", foreign_key: :sandbox_id, dependent: :destroy
    has_many :mock_responses, class_name: "Ai::MockResponse", foreign_key: :sandbox_id, dependent: :destroy
    has_many :test_runs, class_name: "Ai::TestRun", foreign_key: :sandbox_id, dependent: :destroy
    has_many :recorded_interactions, class_name: "Ai::RecordedInteraction", foreign_key: :sandbox_id, dependent: :destroy
    has_many :performance_benchmarks, class_name: "Ai::PerformanceBenchmark", foreign_key: :sandbox_id, dependent: :destroy

    # Validations
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :sandbox_type, presence: true, inclusion: {
      in: %w[standard isolated production_mirror performance security]
    }
    validates :status, presence: true, inclusion: { in: %w[inactive active paused expired deleted] }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :inactive, -> { where(status: "inactive") }
    scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :by_type, ->(type) { where(sandbox_type: type) }
    scope :isolated, -> { where(is_isolated: true) }
    scope :with_recording, -> { where(recording_enabled: true) }

    # Methods
    def active?
      status == "active"
    end

    def inactive?
      status == "inactive"
    end

    def expired?
      expires_at.present? && expires_at < Time.current
    end

    def isolated?
      is_isolated
    end

    def activate!
      return false if expired?

      update!(status: "active")
    end

    def deactivate!
      update!(status: "inactive")
    end

    def pause!
      update!(status: "paused") if active?
    end

    def resume!
      return false if expired?

      update!(status: "active") if status == "paused"
    end

    def expire!
      update!(status: "expired")
    end

    def enable_recording!
      update!(recording_enabled: true)
    end

    def disable_recording!
      update!(recording_enabled: false)
    end

    def record_usage!
      increment!(:total_executions)
      update!(last_used_at: Time.current)
    end

    def get_mock_response(provider_type:, request_data: {})
      return nil unless active?

      mock_responses
        .where(is_active: true, provider_type: provider_type)
        .order(priority: :desc)
        .find { |mock| mock.matches?(request_data) }
    end

    def check_expiration!
      expire! if expires_at.present? && expires_at < Time.current && status != "expired"
    end

    def resource_limit_exceeded?(resource, value)
      return false if resource_limits.blank?

      limit = resource_limits[resource.to_s]
      return false if limit.blank?

      value > limit.to_i
    end
  end
end
