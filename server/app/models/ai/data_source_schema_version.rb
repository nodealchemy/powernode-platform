# frozen_string_literal: true

module Ai
  # One observed/declared response-schema snapshot for a data-source endpoint.
  # Versions are appended monotonically (version 1, 2, 3...) and each carries a
  # classification of how it differs from its immediate predecessor plus the
  # structural diff, so schema drift over time is fully auditable. Written by
  # Ai::DataSources::SchemaDriftService#record_version!.
  class DataSourceSchemaVersion < ApplicationRecord
    self.table_name = "ai_data_source_schema_versions"

    # Associations
    belongs_to :endpoint, class_name: "Ai::DataSourceEndpoint",
               foreign_key: "ai_data_source_endpoint_id"

    # Constants — diff classification of this version vs the previous one.
    #   initial  : first version for the endpoint (no prior schema)
    #   none     : structurally identical to the previous version
    #   additive : only new OPTIONAL fields added (backward compatible)
    #   breaking : a field was removed or changed type (NOT backward compatible)
    CLASSIFICATIONS = %w[initial none additive breaking].freeze

    # JSON column defaults (lambda required for mutable defaults)
    attribute :schema, :json, default: -> { {} }
    attribute :diff, :json, default: -> { {} }

    # Validations
    validates :ai_data_source_endpoint_id, presence: true
    validates :version, presence: true,
              numericality: { only_integer: true, greater_than: 0 },
              uniqueness: { scope: :ai_data_source_endpoint_id }
    validates :classification, presence: true, inclusion: { in: CLASSIFICATIONS }

    # Scopes
    scope :for_endpoint, lambda { |ep|
      where(ai_data_source_endpoint_id: ep.is_a?(Ai::DataSourceEndpoint) ? ep.id : ep)
    }
    scope :ordered, -> { order(version: :asc) }
    scope :latest_first, -> { order(version: :desc) }
    scope :breaking, -> { where(classification: "breaking") }
  end
end
