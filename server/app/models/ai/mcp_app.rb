# frozen_string_literal: true

module Ai
  class McpApp < ApplicationRecord
    self.table_name = "ai_mcp_apps"

    # ==========================================
    # Constants
    # ==========================================
    APP_TYPES = %w[custom template system].freeze
    STATUSES = %w[draft published archived].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    has_many :mcp_app_instances, class_name: "Ai::McpAppInstance",
             foreign_key: :mcp_app_id, dependent: :destroy

    # ==========================================
    # Validations
    # ==========================================
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :app_type, presence: true, inclusion: { in: APP_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :version, presence: true, format: { with: /\A\d+\.\d+\.\d+\z/, message: "must be semver format (e.g., 1.0.0)" }

    # ==========================================
    # Scopes
    # ==========================================
    scope :draft, -> { where(status: "draft") }
    scope :published, -> { where(status: "published") }
    scope :archived, -> { where(status: "archived") }
    scope :by_type, ->(type) { where(app_type: type) }
    scope :custom, -> { where(app_type: "custom") }
    scope :templates, -> { where(app_type: "template") }
    scope :system, -> { where(app_type: "system") }
    scope :recent, -> { order(created_at: :desc) }
    scope :active, -> { where(status: %w[draft published]) }

    # ==========================================
    # Public Methods
    # ==========================================

    def publish!
      update!(status: "published")
    end

    def archive!
      update!(status: "archived")
    end

    def published?
      status == "published"
    end

    def draft?
      status == "draft"
    end

    def archived?
      status == "archived"
    end
  end
end
