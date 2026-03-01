# frozen_string_literal: true

module Ai
  class McpAppInstance < ApplicationRecord
    self.table_name = "ai_mcp_app_instances"

    # ==========================================
    # Constants
    # ==========================================
    STATUSES = %w[created running completed error].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :mcp_app, class_name: "Ai::McpApp", foreign_key: :mcp_app_id
    belongs_to :account
    belongs_to :session, class_name: "Ai::AguiSession", foreign_key: :session_id, optional: true

    # ==========================================
    # Validations
    # ==========================================
    validates :status, presence: true, inclusion: { in: STATUSES }

    # ==========================================
    # Scopes
    # ==========================================
    scope :created_status, -> { where(status: "created") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :errored, -> { where(status: "error") }
    scope :active, -> { where(status: %w[created running]) }
    scope :recent, -> { order(created_at: :desc) }

    # ==========================================
    # Public Methods
    # ==========================================

    def start!
      update!(status: "running", started_at: Time.current)
    end

    def complete!(output = {})
      update!(status: "completed", output_data: output, completed_at: Time.current)
    end

    def error!(error_data = {})
      update!(status: "error", output_data: error_data, completed_at: Time.current)
    end

    def active?
      status.in?(%w[created running])
    end
  end
end
