# frozen_string_literal: true

module Devops
  class SwarmCluster < ApplicationRecord
    self.table_name = "devops_swarm_clusters"

    include Auditable

    ENVIRONMENTS = %w[staging production development custom].freeze
    STATUSES = %w[pending connected disconnected error maintenance].freeze
    MAX_CONSECUTIVE_FAILURES = 5

    belongs_to :account
    has_many :swarm_nodes, class_name: "Devops::SwarmNode", foreign_key: "cluster_id", dependent: :destroy
    has_many :swarm_services, class_name: "Devops::SwarmService", foreign_key: "cluster_id", dependent: :destroy
    has_many :swarm_stacks, class_name: "Devops::SwarmStack", foreign_key: "cluster_id", dependent: :destroy
    has_many :swarm_deployments, class_name: "Devops::SwarmDeployment", foreign_key: "cluster_id", dependent: :destroy
    has_many :swarm_events, class_name: "Devops::SwarmEvent", foreign_key: "cluster_id", dependent: :destroy

    validates :name, presence: true, length: { maximum: 255 }
    validates :name, uniqueness: { scope: :account_id }
    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
    validates :api_endpoint, presence: true, format: { with: /\Ahttps?:\/\// }
    validates :environment, presence: true, inclusion: { in: ENVIRONMENTS }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :sync_interval_seconds, numericality: { greater_than_or_equal_to: 30, less_than_or_equal_to: 3600 }

    scope :connected, -> { where(status: "connected") }
    scope :auto_syncable, -> { where(auto_sync: true, status: "connected") }
    scope :by_environment, ->(env) { where(environment: env) }

    before_validation :generate_slug, on: :create

    def connected?
      status == "connected"
    end

    def pending?
      status == "pending"
    end

    def error?
      status == "error"
    end

    def record_success!
      update!(
        status: "connected",
        consecutive_failures: 0,
        last_synced_at: Time.current
      )
    end

    def record_failure!
      new_failures = consecutive_failures + 1
      new_status = new_failures >= MAX_CONSECUTIVE_FAILURES ? "error" : status
      update!(
        consecutive_failures: new_failures,
        status: new_status
      )
    end

    def cluster_summary
      {
        id: id,
        name: name,
        slug: slug,
        api_endpoint: api_endpoint,
        environment: environment,
        status: status,
        node_count: node_count,
        service_count: service_count,
        last_synced_at: last_synced_at,
        auto_sync: auto_sync,
        tls_verify: tls_verify,
        has_tls_credentials: encrypted_tls_credentials.present?
      }
    end

    def cluster_details
      cluster_summary.merge(
        description: description,
        api_version: api_version,
        swarm_id: swarm_id,
        sync_interval_seconds: sync_interval_seconds,
        consecutive_failures: consecutive_failures,
        metadata: metadata,
        created_at: created_at,
        updated_at: updated_at
      )
    end

    private

    def generate_slug
      return if slug.present?
      return if name.blank?

      base_slug = name.parameterize
      self.slug = base_slug

      counter = 1
      while Devops::SwarmCluster.exists?(slug: slug)
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end
  end
end
