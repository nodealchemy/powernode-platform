# frozen_string_literal: true

module Devops
  class SwarmNode < ApplicationRecord
    self.table_name = "devops_swarm_nodes"

    include Auditable

    ROLES = %w[manager worker].freeze
    AVAILABILITIES = %w[active pause drain].freeze
    STATUSES = %w[ready down disconnected unknown].freeze

    belongs_to :cluster, class_name: "Devops::SwarmCluster"

    validates :docker_node_id, presence: true, uniqueness: { scope: :cluster_id }
    validates :hostname, presence: true
    validates :role, presence: true, inclusion: { in: ROLES }
    validates :availability, presence: true, inclusion: { in: AVAILABILITIES }
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :managers, -> { where(role: "manager") }
    scope :workers, -> { where(role: "worker") }
    scope :ready, -> { where(status: "ready") }
    scope :active_nodes, -> { where(availability: "active") }
    scope :draining, -> { where(availability: "drain") }

    def manager?
      role == "manager"
    end

    def worker?
      role == "worker"
    end

    def leader?
      manager_status == "leader"
    end

    def ready?
      status == "ready"
    end

    def healthy?
      ready? && availability == "active"
    end

    def update_from_docker_data(data)
      update!(
        hostname: data["Description"]["Hostname"],
        role: data["Spec"]["Role"],
        availability: data["Spec"]["Availability"],
        status: data["Status"]["State"],
        manager_status: data.dig("ManagerStatus", "Reachability") || (data.dig("ManagerStatus", "Leader") ? "leader" : nil),
        ip_address: data["Status"]["Addr"],
        engine_version: data.dig("Description", "Engine", "EngineVersion"),
        os: data.dig("Description", "Platform", "OS"),
        architecture: data.dig("Description", "Platform", "Architecture"),
        memory_bytes: data.dig("Description", "Resources", "MemoryBytes"),
        cpu_count: data.dig("Description", "Resources", "NanoCPUs")&.then { |n| (n / 1_000_000_000.0).ceil },
        labels: data.dig("Spec", "Labels") || {},
        last_seen_at: Time.current
      )
    end

    def memory_gb
      return nil unless memory_bytes
      (memory_bytes / 1_073_741_824.0).round(1)
    end

    def node_summary
      {
        id: id,
        docker_node_id: docker_node_id,
        hostname: hostname,
        role: role,
        availability: availability,
        status: status,
        manager_status: manager_status,
        ip_address: ip_address,
        memory_gb: memory_gb,
        cpu_count: cpu_count,
        labels: labels
      }
    end

    def node_details
      node_summary.merge(
        engine_version: engine_version,
        os: os,
        architecture: architecture,
        memory_bytes: memory_bytes,
        last_seen_at: last_seen_at,
        created_at: created_at,
        updated_at: updated_at
      )
    end
  end
end
