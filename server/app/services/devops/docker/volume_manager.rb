# frozen_string_literal: true

module Devops
  module Docker
    class VolumeManager
      def initialize(cluster:)
        @cluster = cluster
        @client = ApiClient.new(cluster)
      end

      def list
        response = @client.volume_list
        volumes = response.is_a?(Hash) ? (response["Volumes"] || []) : response
        volumes.map { |v| serialize_volume(v) }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to list volumes for cluster #{@cluster.name}: #{e.message}")
        raise
      end

      def inspect_volume(id)
        serialize_volume(@client.volume_inspect(id))
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to inspect volume #{id}: #{e.message}")
        raise
      end

      def create(params)
        result = @client.volume_create(params)
        Rails.logger.info("Created volume #{params["Name"]} on cluster #{@cluster.name}")
        { success: true, name: result["Name"] }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to create volume: #{e.message}")
        { success: false, error: e.message }
      end

      def remove(id)
        @client.volume_delete(id)
        Rails.logger.info("Removed volume #{id} from cluster #{@cluster.name}")
        { success: true }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to remove volume #{id}: #{e.message}")
        { success: false, error: e.message }
      end

      private

      def serialize_volume(data)
        {
          name: data["Name"],
          driver: data["Driver"],
          mountpoint: data["Mountpoint"],
          scope: data["Scope"],
          labels: data["Labels"] || {},
          created_at: data["CreatedAt"]
        }
      end
    end
  end
end
