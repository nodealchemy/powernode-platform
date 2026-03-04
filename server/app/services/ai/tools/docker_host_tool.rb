# frozen_string_literal: true

module Ai
  module Tools
    class DockerHostTool < BaseTool
      include Concerns::DockerContextResolvable

      REQUIRED_PERMISSION = "docker.hosts.read"

      def self.definition
        {
          name: "docker_host_management",
          description: "Manage Docker hosts: list, inspect, sync, and test connections",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" }
          }
        }
      end

      def self.action_definitions
        {
          "docker_list_hosts" => {
            description: "List all Docker hosts registered in the account with connection status and resource counts",
            parameters: {}
          },
          "docker_get_host" => {
            description: "Get detailed information about a Docker host including OS, resources, and Docker version",
            parameters: {
              host_id: { type: "string", required: true, description: "Docker host ID, slug, or name" }
            }
          },
          "docker_sync_host" => {
            description: "Synchronize a Docker host: fetch containers and images from the Docker daemon and update local records",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name (auto-selects if only one)" }
            }
          },
          "docker_test_host" => {
            description: "Test the connection to a Docker host and return system information",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name (auto-selects if only one)" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "docker_list_hosts" then list_hosts(params)
        when "docker_get_host" then get_host(params)
        when "docker_sync_host" then sync_host(params)
        when "docker_test_host" then test_host(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      rescue ArgumentError => e
        { success: false, error: e.message }
      rescue Devops::Docker::ApiClient::ApiError => e
        { success: false, error: "Docker API error: #{e.message}" }
      end

      private

      def list_hosts(_params)
        hosts = account.devops_docker_hosts.order(:name)

        {
          success: true,
          hosts: hosts.map { |h| h.host_summary },
          count: hosts.size
        }
      end

      def get_host(params)
        host = resolve_host(params[:host_id])

        {
          success: true,
          host: host.host_details,
          containers: {
            total: host.docker_containers.count,
            running: host.docker_containers.where(state: "running").count
          },
          images: {
            total: host.docker_images.count
          }
        }
      end

      def sync_host(params)
        host = resolve_host(params[:host_id])
        manager = Devops::Docker::HostManager.new(account: account)

        result = manager.sync_host(host)
        result.merge(host_name: host.name)
      end

      def test_host(params)
        host = resolve_host(params[:host_id])
        manager = Devops::Docker::HostManager.new(account: account)

        result = manager.test_connection(host)
        result.merge(host_name: host.name)
      end
    end
  end
end
