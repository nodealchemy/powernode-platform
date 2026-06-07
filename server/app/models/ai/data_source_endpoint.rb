# frozen_string_literal: true

module Ai
  class DataSourceEndpoint < ApplicationRecord
    self.table_name = "ai_data_source_endpoints"

    # Concerns
    include Auditable

    # Associations
    belongs_to :data_source, class_name: "Ai::DataSource", foreign_key: "ai_data_source_id"
    has_many :queries, class_name: "Ai::DataSourceQuery",
             foreign_key: "ai_data_source_endpoint_id", dependent: :nullify
    has_many :schema_versions, class_name: "Ai::DataSourceSchemaVersion",
             foreign_key: "ai_data_source_endpoint_id", dependent: :destroy
    has_many :expectations, class_name: "Ai::DataSourceExpectation",
             foreign_key: "ai_data_source_endpoint_id", dependent: :destroy
    has_many :subscriptions, class_name: "Ai::DataSourceSubscription",
             foreign_key: "ai_data_source_endpoint_id", dependent: :destroy

    # Auditable resolves the account through the parent source (this model has no
    # direct account association). Without this, AuditLog.create! fails its
    # required belongs_to :account and audit writes silently no-op.
    delegate :account, to: :data_source, allow_nil: true

    # Constants
    HTTP_METHODS = %w[GET POST PUT PATCH DELETE HEAD].freeze
    RESPONSE_FORMATS = %w[json xml csv ndjson rss atom html text binary].freeze
    CHANGE_DETECTION_STRATEGIES = %w[etag last_modified content_hash polling none].freeze

    # Phase 2b schema-drift classification tokens (mirror
    # Ai::DataSourceSchemaVersion::CLASSIFICATIONS) — the values that may land in
    # a query log row's schema_drift column when track_schema is enabled.
    SCHEMA_DRIFT_CLASSIFICATIONS = Ai::DataSourceSchemaVersion::CLASSIFICATIONS

    # Phase 2b quality expectation enums, re-exported off the endpoint for callers
    # that build expectations relative to an endpoint without reaching into the
    # expectation model directly.
    EXPECTATION_RULE_TYPES = Ai::DataSourceExpectation::RULE_TYPES
    EXPECTATION_SEVERITIES = Ai::DataSourceExpectation::SEVERITIES

    # JSON column defaults (lambda required for mutable defaults)
    attribute :query_template, :json, default: -> { {} }
    attribute :body_template, :json, default: -> { {} }
    attribute :response_mapping, :json, default: -> { {} }
    attribute :response_schema, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }
    attribute :contract, :json, default: -> { {} }
    # Outbound pagination config consumed by the REST adapter / QueryService.
    # Blank ({}) == OFF (single request, unchanged behavior).
    attribute :pagination, :json, default: -> { {} }

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :ai_data_source_id, presence: true
    validates :slug, presence: true, length: { maximum: 100 },
              uniqueness: { scope: :ai_data_source_id },
              format: { with: /\A[a-z0-9_-]+\z/, message: "must be lowercase alphanumeric with hyphens/underscores" }
    validates :http_method, presence: true, inclusion: { in: HTTP_METHODS }
    validates :response_format, inclusion: { in: RESPONSE_FORMATS }, allow_nil: true
    validates :change_detection, inclusion: { in: CHANGE_DETECTION_STRATEGIES }, allow_nil: true
    validates :cache_ttl_seconds, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    # Callbacks
    before_validation :generate_slug, on: :create

    # Scopes
    scope :for_data_source, ->(ds) { where(ai_data_source_id: ds.is_a?(Ai::DataSource) ? ds.id : ds) }
    scope :monitorable, -> { where(monitorable: true) }

    def to_param
      slug
    end

    private

    def generate_slug
      return if slug.present?

      base = name.to_s.parameterize.underscore.first(90)
      self.slug = base
      counter = 1
      while self.class.where(ai_data_source_id: ai_data_source_id, slug: slug).where.not(id: id).exists?
        self.slug = "#{base}_#{counter}"
        counter += 1
      end
    end
  end
end
