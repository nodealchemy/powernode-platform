# frozen_string_literal: true

module Devops
  module Docker
    class HostManager
      def initialize(account:)
        @account = account
      end

      def register_host(params)
        host = @account.devops_docker_hosts.new(params)

        unless host.save
          raise ActiveRecord::RecordInvalid, host
        end

        begin
          client = ApiClient.new(host)
          client.ping
          info_result = client.info

          host.update!(
            docker_version: info_result["ServerVersion"],
            os_type: info_result["OperatingSystem"],
            architecture: info_result["Architecture"],
            kernel_version: info_result["KernelVersion"],
            memory_bytes: info_result["MemTotal"],
            cpu_count: info_result["NCPU"],
            container_count: info_result["Containers"] || 0,
            image_count: info_result["Images"] || 0,
            api_version: "v#{info_result['ApiVersion'] || '1.45'}",
            status: "connected",
            last_synced_at: Time.current
          )

          Rails.logger.info("Registered Docker host #{host.name} (#{host.api_endpoint})")
        rescue ApiClient::ApiError => e
          host.update!(status: "error")
          Rails.logger.error("Failed to connect to Docker host #{host.name}: #{e.message}")
        end

        host
      end

      def test_connection(host)
        client = ApiClient.new(host)
        client.ping
        info_result = client.info

        host.record_success!

        {
          success: true,
          api_version: info_result["ApiVersion"],
          server_version: info_result["ServerVersion"],
          os: info_result["OperatingSystem"],
          architecture: info_result["Architecture"],
          kernel_version: info_result["KernelVersion"],
          containers: info_result["Containers"],
          images: info_result["Images"],
          memory_total: info_result["MemTotal"],
          cpus: info_result["NCPU"]
        }
      rescue ApiClient::ConnectionError => e
        host.record_failure!
        { success: false, error: "Connection failed: #{e.message}" }
      rescue ApiClient::ApiError => e
        host.record_failure!
        { success: false, error: e.message }
      end

      def sync_host(host)
        client = ApiClient.new(host)

        containers = client.container_list(all: true)
        sync_containers(host, containers)

        images = client.image_list
        sync_images(host, images)

        host.update!(
          container_count: host.docker_containers.count,
          image_count: host.docker_images.count,
          last_synced_at: Time.current,
          status: "connected",
          consecutive_failures: 0
        )

        Rails.logger.info("Synced Docker host #{host.name}: #{containers.size} containers, #{images.size} images")
        { success: true, containers: containers.size, images: images.size }
      rescue ApiClient::ApiError => e
        host.record_failure!
        Rails.logger.error("Failed to sync Docker host #{host.name}: #{e.message}")
        { success: false, error: e.message }
      end

      def remove_host(host)
        host.destroy!
        Rails.logger.info("Removed Docker host #{host.name} from account #{@account.id}")
        { success: true }
      end

      def available_containers(host)
        client = ApiClient.new(host)
        docker_containers = client.container_list(all: true)
        imported_ids = host.docker_containers.pluck(:docker_container_id)

        docker_containers.map do |dc|
          {
            docker_container_id: dc["Id"],
            name: (dc["Names"]&.first || "unknown").sub(/\A\//, ""),
            image: dc["Image"] || "unknown",
            state: dc["State"] || "unknown",
            status_text: dc["Status"],
            ports: extract_container_ports(dc["Ports"] || []),
            already_imported: imported_ids.include?(dc["Id"])
          }
        end
      end

      def import_containers(host, docker_container_ids)
        client = ApiClient.new(host)
        docker_containers = client.container_list(all: true)
        imported = []

        docker_containers.each do |dc|
          next unless docker_container_ids.include?(dc["Id"])
          next if host.docker_containers.exists?(docker_container_id: dc["Id"])

          container = host.docker_containers.new(docker_container_id: dc["Id"])
          update_container_from_docker(container, dc)
          imported << container
        end

        imported
      end

      def available_images(host)
        client = ApiClient.new(host)
        docker_images = client.image_list
        imported_ids = host.docker_images.pluck(:docker_image_id)

        docker_images.map do |di|
          {
            docker_image_id: di["Id"],
            repo_tags: di["RepoTags"] || [],
            size_bytes: di["Size"],
            container_count: di["Containers"] || 0,
            already_imported: imported_ids.include?(di["Id"])
          }
        end
      end

      def import_images(host, docker_image_ids)
        client = ApiClient.new(host)
        docker_images = client.image_list
        imported = []

        docker_images.each do |di|
          next unless docker_image_ids.include?(di["Id"])
          next if host.docker_images.exists?(docker_image_id: di["Id"])

          image = host.docker_images.new(docker_image_id: di["Id"])
          update_image_from_docker(image, di)
          imported << image
        end

        imported
      end

      private

      def sync_containers(host, docker_containers)
        remote_ids = docker_containers.map { |c| c["Id"] }

        # Remove containers that no longer exist on the host
        host.docker_containers.where.not(docker_container_id: remote_ids).destroy_all

        # Upsert all containers from remote
        docker_containers.each do |dc|
          container = host.docker_containers.find_or_initialize_by(docker_container_id: dc["Id"])
          update_container_from_docker(container, dc)
        end
      end

      def sync_images(host, docker_images)
        remote_ids = docker_images.map { |i| i["Id"] }

        # Remove images that no longer exist on the host
        host.docker_images.where.not(docker_image_id: remote_ids).destroy_all

        # Upsert all images from remote
        docker_images.each do |di|
          image = host.docker_images.find_or_initialize_by(docker_image_id: di["Id"])
          update_image_from_docker(image, di)
        end
      end

      def update_container_from_docker(container, dc)
        container.assign_attributes(
          name: (dc["Names"]&.first || "unknown").sub(/\A\//, ""),
          image: dc["Image"] || "unknown",
          image_id: dc["ImageID"],
          state: dc["State"] || "unknown",
          status_text: dc["Status"],
          ports: extract_container_ports(dc["Ports"] || []),
          mounts: dc["Mounts"] || [],
          networks: dc.dig("NetworkSettings", "Networks") || {},
          labels: dc["Labels"] || {},
          command: dc["Command"],
          last_seen_at: Time.current
        )
        container.save!
      end

      def update_image_from_docker(image, di)
        image.assign_attributes(
          repo_tags: di["RepoTags"] || [],
          repo_digests: di["RepoDigests"] || [],
          size_bytes: di["Size"],
          virtual_size: di["VirtualSize"],
          container_count: di["Containers"] || 0,
          labels: di["Labels"] || {},
          docker_created_at: di["Created"] ? Time.at(di["Created"]) : nil,
          last_seen_at: Time.current
        )
        image.save!
      end

      def extract_container_ports(ports)
        ports.map do |port|
          {
            ip: port["IP"],
            private_port: port["PrivatePort"],
            public_port: port["PublicPort"],
            type: port["Type"]
          }
        end
      end
    end
  end
end
