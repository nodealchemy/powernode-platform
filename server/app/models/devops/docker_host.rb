# frozen_string_literal: true

module Devops
  class DockerHost < ApplicationRecord
    self.table_name = "devops_docker_hosts"

    include Auditable

    ENVIRONMENTS = %w[staging production development custom].freeze
    STATUSES = %w[pending connected disconnected error maintenance].freeze
    MAX_CONSECUTIVE_FAILURES = 5

    belongs_to :account
    has_many :docker_containers, class_name: "Devops::DockerContainer", foreign_key: "docker_host_id", dependent: :destroy
    has_many :docker_images, class_name: "Devops::DockerImage", foreign_key: "docker_host_id", dependent: :destroy
    has_many :docker_events, class_name: "Devops::DockerEvent", foreign_key: "docker_host_id", dependent: :destroy
    has_many :docker_activities, class_name: "Devops::DockerActivity", foreign_key: "docker_host_id", dependent: :destroy

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

    def host_summary
      {
        id: id,
        name: name,
        slug: slug,
        api_endpoint: api_endpoint,
        environment: environment,
        status: status,
        container_count: container_count,
        image_count: image_count,
        last_synced_at: last_synced_at,
        auto_sync: auto_sync,
        tls_verify: tls_verify,
        has_tls_credentials: encrypted_tls_credentials.present?
      }
    end

    def host_details
      host_summary.merge(
        description: description,
        api_version: api_version,
        docker_version: docker_version,
        os_type: os_type,
        architecture: architecture,
        kernel_version: kernel_version,
        memory_bytes: memory_bytes,
        cpu_count: cpu_count,
        storage_bytes: storage_bytes,
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
      while Devops::DockerHost.exists?(slug: slug)
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end
  end
end
