# frozen_string_literal: true

module Devops
  class PortAllocatorService
    class AllocationError < StandardError; end
    class NoPortAvailableError < AllocationError; end

    AGENT_PORT_RANGE = (7000..7499).freeze
    APP_PORT_RANGE = (6000..6199).freeze
    GENERAL_PORT_RANGE = (7500..7999).freeze

    # Hex for "PORT" — namespace for pg_advisory_xact_lock
    LOCK_NAMESPACE = 0x504F5254

    # Allocate a port on a host with advisory locking to prevent races.
    #
    # @param host_identifier [String] docker host ID, swarm cluster ID, or "localhost"
    # @param allocatable [ActiveRecord::Base] the record owning this port (ContainerInstance, Mission, etc.)
    # @param purpose [String] "mcp_bridge", "app_server", "debug", etc.
    # @param port_range [Range] explicit range override
    # @param protocol [String] "tcp" or "udp"
    # @param expires_at [DateTime] optional TTL for auto-release
    # @return [Integer] the allocated port number
    def allocate!(host_identifier:, allocatable:, purpose:, port_range: nil, protocol: "tcp", expires_at: nil)
      range = port_range || range_for_purpose(purpose)

      # Probe Docker host ports OUTSIDE the transaction to avoid poisoning
      # the PG transaction if the probe query hits an error.
      docker_ports = probe_docker_ports(host_identifier)

      ActiveRecord::Base.transaction do
        acquire_advisory_lock!(host_identifier)

        db_ports = Devops::PortAllocation
          .active
          .where(host_identifier: host_identifier, protocol: protocol)
          .pluck(:port)
          .to_set

        occupied = db_ports | docker_ports
        port = range.find { |p| !occupied.include?(p) }

        raise NoPortAvailableError, "No available ports in #{range} on host #{host_identifier}" unless port

        Devops::PortAllocation.create!(
          account: allocatable.account,
          port: port,
          protocol: protocol,
          host_identifier: host_identifier,
          allocatable: allocatable,
          purpose: purpose,
          status: "active",
          expires_at: expires_at
        )

        port
      end
    end

    # Release all active allocations for a given allocatable.
    #
    # @param allocatable [ActiveRecord::Base] the record whose ports to release
    def release!(allocatable:)
      Devops::PortAllocation
        .active
        .where(allocatable: allocatable)
        .find_each(&:release!)
    end

    # Query Docker host for occupied ports and union with DB-tracked ports.
    #
    # @param host_identifier [String]
    # @return [Set<Integer>] occupied port numbers
    def probe_host_ports(host_identifier:)
      db_ports = Devops::PortAllocation
        .active
        .for_host(host_identifier)
        .pluck(:port)
        .to_set

      docker_ports = probe_docker_ports(host_identifier)

      db_ports | docker_ports
    end

    # Release allocations that have exceeded their TTL.
    # @return [Integer] number of released allocations
    def cleanup_expired!
      count = 0
      Devops::PortAllocation.expired.find_each do |allocation|
        allocation.release!
        count += 1
        Rails.logger.info "[PortAllocator] Released expired allocation: port #{allocation.port} on #{allocation.host_identifier}"
      end
      Rails.logger.info "[PortAllocator] Released #{count} expired port allocations" if count > 0
      count
    end

    private

    def range_for_purpose(purpose)
      case purpose
      when "mcp_bridge"  then AGENT_PORT_RANGE
      when "app_server"  then APP_PORT_RANGE
      else GENERAL_PORT_RANGE
      end
    end

    def acquire_advisory_lock!(host_identifier)
      lock_key = Zlib.crc32(host_identifier) & 0x7FFFFFFF
      ActiveRecord::Base.connection.execute(
        "SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE}, #{lock_key})"
      )
    end

    def occupied_ports(host_identifier, protocol)
      db_ports = Devops::PortAllocation
        .active
        .where(host_identifier: host_identifier, protocol: protocol)
        .pluck(:port)
        .to_set

      docker_ports = probe_docker_ports(host_identifier)

      db_ports | docker_ports
    end

    def probe_docker_ports(host_identifier)
      docker_host = Devops::DockerHost.find_by(slug: host_identifier) ||
                    Devops::DockerHost.find_by(name: host_identifier)
      return Set.new unless docker_host&.connected?

      client = Devops::Docker::ApiClient.new(docker_host)
      containers = client.container_list(all: false)

      ports = Set.new
      containers.each do |container|
        (container.dig("Ports") || []).each do |port_mapping|
          public_port = port_mapping["PublicPort"]
          ports << public_port if public_port
        end
      end

      ports
    rescue StandardError => e
      Rails.logger.warn "[PortAllocator] Docker probe failed for #{host_identifier}: #{e.message}"
      Set.new
    end
  end
end
