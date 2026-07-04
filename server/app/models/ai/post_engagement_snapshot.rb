# frozen_string_literal: true

module Ai
  # One point in a published post's engagement time-series, recorded by
  # Ai::Growth::EngagementIngestionService off a governed
  # Ai::DataSources::QueryService fetch of the provider's metrics endpoint.
  # High-frequency operational data (like Ai::DataSourceQuery) — no Auditable
  # concern here; the publish event itself is audited on Ai::PublishedPost.
  class PostEngagementSnapshot < ApplicationRecord
    self.table_name = "ai_post_engagement_snapshots"

    # Associations
    belongs_to :account
    belongs_to :published_post, class_name: "Ai::PublishedPost", foreign_key: "ai_published_post_id"

    # JSON column defaults (lambda required for mutable defaults)
    attribute :raw_metrics, :json, default: -> { {} }

    # Validations
    validates :captured_at, presence: true

    # Scopes
    scope :for_account, ->(account) { where(account_id: account.is_a?(Account) ? account.id : account) }
    scope :chronological, -> { order(captured_at: :asc) }
  end
end
