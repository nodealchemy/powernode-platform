# frozen_string_literal: true

module Ai
  # A single data-quality expectation (Great-Expectations-style rule) for a
  # data-source endpoint. Active expectations are evaluated over the canonical
  # records of a fetch by Ai::DataSources::QualityService; an ERROR-severity
  # failure fails the batch (and can trigger quarantine), while a WARN-severity
  # failure only lowers the quality score.
  class DataSourceExpectation < ApplicationRecord
    self.table_name = "ai_data_source_expectations"

    # Associations
    belongs_to :endpoint, class_name: "Ai::DataSourceEndpoint",
               foreign_key: "ai_data_source_endpoint_id"

    # Constants
    #   required_fields : every record must contain config["fields"]
    #   min_records     : record count >= config["min"]
    #   max_records     : record count <= config["max"]
    #   non_null        : config["fields"] must be present (non-null) on every record
    #   allowed_values  : config["field"] value must be within config["values"]
    #   distribution    : config["field"] null/blank ratio must stay <= config["max_null_ratio"]
    RULE_TYPES = %w[required_fields min_records max_records non_null allowed_values distribution].freeze

    # warn  : failure lowers the quality score but the batch still passes
    # error : failure fails the batch (passed=false) and can trigger quarantine
    SEVERITIES = %w[warn error].freeze

    # JSON column defaults (lambda required for mutable defaults)
    attribute :config, :json, default: -> { {} }

    # Validations
    validates :ai_data_source_endpoint_id, presence: true
    validates :name, presence: true, length: { maximum: 255 }
    validates :rule_type, presence: true, inclusion: { in: RULE_TYPES }
    validates :severity, presence: true, inclusion: { in: SEVERITIES }

    # Scopes
    scope :for_endpoint, lambda { |ep|
      where(ai_data_source_endpoint_id: ep.is_a?(Ai::DataSourceEndpoint) ? ep.id : ep)
    }
    scope :active, -> { where(is_active: true) }
    scope :errors, -> { where(severity: "error") }
  end
end
