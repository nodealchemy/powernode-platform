# frozen_string_literal: true

module Ai
  # Provenance record for a post published through a connected data source's
  # write endpoint (e.g. x-com's "Create post"). Created by
  # Ai::Growth::PublishedPostRecorder off the FetchEnvelope a successful
  # governed write returns; growth-analytics engagement snapshots
  # (Ai::PostEngagementSnapshot) hang off this record's time-series.
  class PublishedPost < ApplicationRecord
    self.table_name = "ai_published_posts"

    include Auditable

    # Associations
    belongs_to :account
    belongs_to :data_source, class_name: "Ai::DataSource", foreign_key: "ai_data_source_id"
    belongs_to :endpoint, class_name: "Ai::DataSourceEndpoint", foreign_key: "ai_data_source_endpoint_id", optional: true
    belongs_to :requesting_agent, class_name: "Ai::Agent", foreign_key: "requesting_agent_id", optional: true
    has_many :engagement_snapshots, class_name: "Ai::PostEngagementSnapshot",
             foreign_key: "ai_published_post_id", dependent: :destroy

    # JSON column defaults (lambda required for mutable defaults)
    attribute :metadata, :json, default: -> { {} }

    # Validations
    validates :source_type, presence: true
    validates :external_id, presence: true, uniqueness: { scope: :ai_data_source_id }
    validates :published_at, presence: true

    # Scopes
    scope :for_account, ->(account) { where(account_id: account.is_a?(Account) ? account.id : account) }
    scope :for_data_source, ->(ds) { where(ai_data_source_id: ds.is_a?(Ai::DataSource) ? ds.id : ds) }
    scope :recent, ->(limit = 50) { order(published_at: :desc).limit(limit) }

    # Latest recorded snapshot, if any (for a quick "current engagement" read
    # without pulling the full time-series).
    def latest_snapshot
      engagement_snapshots.order(captured_at: :desc).first
    end
  end
end
