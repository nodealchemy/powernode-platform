# frozen_string_literal: true

module Ai
  class DataConnector < ApplicationRecord
    self.table_name = "ai_data_connectors"

    CONNECTOR_TYPES = %w[notion confluence google_drive dropbox github s3 database api web_scraper].freeze
    SYNC_FREQUENCIES = %w[manual hourly daily weekly monthly].freeze

    # Associations
    belongs_to :account
    belongs_to :knowledge_base, class_name: "Ai::KnowledgeBase"
    belongs_to :created_by, class_name: "User", optional: true

    # Validations
    validates :name, presence: true
    validates :connector_type, presence: true, inclusion: { in: CONNECTOR_TYPES }
    validates :status, inclusion: { in: %w[active paused error disconnected] }
    validates :sync_frequency, inclusion: { in: SYNC_FREQUENCIES }, allow_nil: true

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :due_for_sync, -> { active.where("next_sync_at <= ?", Time.current) }
    scope :by_type, ->(type) { where(connector_type: type) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }

    # Callbacks
    before_create :set_initial_sync_time

    # Status transitions
    def activate!
      update!(status: "active")
      schedule_next_sync!
    end

    def pause!
      update!(status: "paused", next_sync_at: nil)
    end

    def mark_error!(error_message)
      update!(
        status: "error",
        sync_errors: sync_errors + 1,
        last_sync_result: { error: error_message, timestamp: Time.current.iso8601 }
      )
    end

    def disconnect!
      update!(status: "disconnected", next_sync_at: nil)
    end

    # Sync operations
    def record_sync!(result)
      success = result[:success] || false

      update!(
        last_sync_at: Time.current,
        documents_synced: success ? documents_synced + (result[:documents_count] || 0) : documents_synced,
        sync_errors: success ? 0 : sync_errors + 1,
        last_sync_result: result
      )

      schedule_next_sync! if active?
    end

    def schedule_next_sync!
      return unless sync_frequency.present? && sync_frequency != "manual"

      interval = case sync_frequency
                 when "hourly" then 1.hour
                 when "daily" then 1.day
                 when "weekly" then 1.week
                 when "monthly" then 1.month
                 else 1.day
      end

      update!(next_sync_at: Time.current + interval)
    end

    # Status checks
    def active?
      status == "active"
    end

    def needs_sync?
      active? && next_sync_at.present? && next_sync_at <= Time.current
    end

    # Connection config helpers
    def credentials
      connection_config["credentials"] || {}
    end

    def set_credentials!(creds)
      update!(connection_config: connection_config.merge("credentials" => creds))
    end

    private

    def set_initial_sync_time
      return if next_sync_at.present?

      self.next_sync_at = Time.current if sync_frequency.present? && sync_frequency != "manual"
    end
  end
end
