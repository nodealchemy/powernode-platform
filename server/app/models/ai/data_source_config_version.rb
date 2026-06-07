# frozen_string_literal: true

module Ai
  # One CREDENTIAL-FREE config snapshot ("manifest") of a data source and its
  # endpoints. Versions are appended monotonically (version 1, 2, 3...) per source
  # by Ai::DataSources::ConfigPortabilityService#snapshot!, capturing the portable
  # export manifest at that point in time so a source's config can be audited and
  # rolled back. Mirrors Ai::DataSourceSchemaVersion's append-only pattern, but
  # scoped to the whole source's PORTABLE config rather than one endpoint's schema.
  #
  # SECURITY: the +manifest+ jsonb is produced by ConfigPortabilityService#export,
  # which strips ALL secret material (credentials, encrypted fields, secret-ish
  # auth_config values). A persisted version row therefore NEVER contains secrets.
  class DataSourceConfigVersion < ApplicationRecord
    self.table_name = "ai_data_source_config_versions"

    # Constants — provenance of how a version row was produced.
    #   auto     : captured automatically (e.g. before an automated config change)
    #   manual   : captured by an explicit user/operator snapshot
    #   rollback : captured to preserve the pre-rollback state when rolling back
    CREATED_BY_TYPES = %w[auto manual rollback].freeze

    # Associations
    belongs_to :data_source, class_name: "Ai::DataSource",
               foreign_key: "ai_data_source_id"
    belongs_to :account

    # JSON column defaults (lambda required for mutable defaults)
    attribute :manifest, :json, default: -> { {} }

    # Validations
    validates :ai_data_source_id, presence: true
    validates :version, presence: true,
              numericality: { only_integer: true, greater_than: 0 },
              uniqueness: { scope: :ai_data_source_id }
    validates :created_by_type, presence: true, inclusion: { in: CREATED_BY_TYPES }

    # Scopes
    scope :for_data_source, lambda { |ds|
      where(ai_data_source_id: ds.is_a?(Ai::DataSource) ? ds.id : ds)
    }
    scope :ordered, -> { order(version: :asc) }
    scope :latest_first, -> { order(version: :desc) }

    # Next sequential version number for a data source (1 when none exist).
    # Mirrors the monotonic-append contract of the schema-version history.
    def self.next_version_for(data_source)
      for_data_source(data_source).maximum(:version).to_i + 1
    end
  end
end
