# frozen_string_literal: true

module Ai
  class DataSourceQuery < ApplicationRecord
    self.table_name = "ai_data_source_queries"

    # Associations
    belongs_to :data_source, class_name: "Ai::DataSource", foreign_key: "ai_data_source_id"
    belongs_to :endpoint, class_name: "Ai::DataSourceEndpoint",
               foreign_key: "ai_data_source_endpoint_id", optional: true

    # Constants
    STATUSES = %w[success error timeout rate_limited blocked cached].freeze
    SERVED_STAGES = %w[fresh cache stale_while_revalidate stale_if_error].freeze
    POLICY_DECISIONS = %w[allow deny mask].freeze

    # JSON column defaults (lambda required for mutable defaults)
    attribute :metadata, :json, default: -> { {} }

    # Validations
    validates :ai_data_source_id, presence: true

    # Scopes
    scope :for_data_source, ->(ds) { where(ai_data_source_id: ds.is_a?(Ai::DataSource) ? ds.id : ds) }
    scope :for_account, ->(account) { where(account_id: account.is_a?(Account) ? account.id : account) }
    scope :successful, -> { where(status: "success") }
    scope :failed, -> { where.not(status: "success") }
    scope :cached, -> { where(cached: true) }
    scope :recent, -> { order(created_at: :desc) }
  end
end
