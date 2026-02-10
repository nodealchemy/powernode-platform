# frozen_string_literal: true

module Ai
  class AguiSession < ApplicationRecord
    self.table_name = "ai_agui_sessions"

    # ==========================================
    # Constants
    # ==========================================
    STATUSES = %w[idle running completed error cancelled].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :user, optional: true
    has_many :agui_events, class_name: "Ai::AguiEvent",
             foreign_key: :session_id, dependent: :destroy
    has_many :mcp_app_instances, class_name: "Ai::McpAppInstance",
             foreign_key: :session_id, dependent: :nullify

    # ==========================================
    # Validations
    # ==========================================
    validates :thread_id, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :sequence_number, numericality: { greater_than_or_equal_to: 0 }

    # ==========================================
    # Scopes
    # ==========================================
    scope :idle, -> { where(status: "idle") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :errored, -> { where(status: "error") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :active, -> { where(status: %w[idle running]) }
    scope :expired, -> { where("expires_at IS NOT NULL AND expires_at < ?", Time.current) }
    scope :recent, -> { order(created_at: :desc) }
    scope :by_thread, ->(thread_id) { where(thread_id: thread_id) }
    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }

    # ==========================================
    # Callbacks
    # ==========================================
    before_validation :set_defaults, on: :create

    # ==========================================
    # Public Methods
    # ==========================================

    def start_run!(run_id: nil)
      update!(
        status: "running",
        run_id: run_id || generate_run_id,
        started_at: Time.current
      )
    end

    def complete_run!
      update!(
        status: "completed",
        completed_at: Time.current
      )
    end

    def error_run!(error_message = nil)
      update!(
        status: "error",
        completed_at: Time.current
      )
    end

    def cancel_run!
      update!(
        status: "cancelled",
        completed_at: Time.current
      )
    end

    def increment_sequence!
      increment!(:sequence_number)
      sequence_number
    end

    def active?
      status.in?(%w[idle running])
    end

    def expired?
      expires_at.present? && expires_at < Time.current
    end

    private

    def set_defaults
      self.status ||= "idle"
      self.state ||= {}
      self.messages ||= []
      self.tools ||= []
      self.context ||= []
      self.capabilities ||= {}
      self.sequence_number ||= 0
    end

    def generate_run_id
      "run_#{SecureRandom.hex(12)}"
    end
  end
end
