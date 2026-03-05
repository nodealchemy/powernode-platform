# frozen_string_literal: true

module Ai
  module Missions
    class AppLaunchService
      class LaunchError < StandardError; end

      PORT_RANGE = (6000..6199).freeze

      attr_reader :mission, :account

      def initialize(mission:)
        @mission = mission
        @account = mission.account
      end

      def allocate_port!
        cluster = resolve_deploy_cluster
        host_id = cluster&.slug || "localhost"

        port = Devops::PortAllocatorService.new.allocate!(
          host_identifier: host_id,
          allocatable: mission,
          purpose: "app_server",
          port_range: PORT_RANGE,
          expires_at: 24.hours.from_now
        )

        mission.update!(deployed_port: port)
        port
      rescue Devops::PortAllocatorService::NoPortAvailableError
        raise LaunchError, "No available ports in range #{PORT_RANGE}"
      end

      def preview_url(port)
        hostname = resolve_deploy_cluster&.public_hostname || "localhost"
        "http://#{hostname}:#{port}"
      end

      def launch!(branch:)
        port = mission.deployed_port || allocate_port!

        repository = mission.repository
        raise LaunchError, "No repository linked to mission" unless repository

        credential = find_credential(repository)
        raise LaunchError, "No git credentials found" unless credential

        client = Devops::Git::ApiClient.for(credential)
        owner = repository.owner
        repo_name = repository.name

        callback_url = build_callback_url

        result = client.trigger_workflow(
          owner, repo_name,
          "ai-app-launch.yml",
          branch,
          {
            mission_id: mission.id,
            branch: branch,
            port: port.to_s,
            callback_url: callback_url,
            app_type: "auto"
          }
        )

        unless result[:success]
          raise LaunchError, "Failed to trigger deploy workflow: #{result[:error]}"
        end

        result
      end

      def record_deployment!(container_id:, url:)
        mission.update!(
          deployed_container_id: container_id,
          deployed_url: url
        )

        MissionChannel.broadcast_mission_event(mission.id, "deployed", {
          mission_id: mission.id,
          url: url,
          port: mission.deployed_port,
          container_id: container_id
        })
      end

      def release_port!
        mission.update!(deployed_port: nil)
      end

      def cleanup!
        Devops::PortAllocatorService.new.release!(allocatable: mission)
        mission.update!(
          deployed_port: nil,
          deployed_url: nil,
          deployed_container_id: nil
        )
      end

      private

      def resolve_deploy_cluster
        account.devops_swarm_clusters.connected.first
      end

      def find_credential(repository)
        account.git_provider_credentials
          .joins(:provider)
          .where(git_providers: { provider_type: repository.provider_type })
          .first
      end

      def build_callback_url
        base = if Rails.application.config.respond_to?(:webhook_base_url)
                 Rails.application.config.webhook_base_url
               else
                 ENV["WEBHOOK_BASE_URL"]
               end

        raise LaunchError, "WEBHOOK_BASE_URL must be configured (set env var or Rails config)" unless base.present?

        "#{base}/api/v1/ai/missions/#{mission.id}/deploy_callback"
      end
    end
  end
end
