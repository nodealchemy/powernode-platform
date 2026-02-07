# frozen_string_literal: true

module Devops
  module Docker
    class NetworkManager
      def initialize(cluster:)
        @cluster = cluster
        @client = ApiClient.new(cluster)
      end

      def list
        @client.network_list
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to list networks for cluster #{@cluster.name}: #{e.message}")
        raise
      end

      def inspect_network(id)
        @client.network_inspect(id)
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to inspect network #{id}: #{e.message}")
        raise
      end

      def create(params)
        result = @client.network_create(params)
        Rails.logger.info("Created network #{params["Name"]} on cluster #{@cluster.name}")
        { success: true, id: result["Id"] }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to create network: #{e.message}")
        { success: false, error: e.message }
      end

      def remove(id)
        @client.network_delete(id)
        Rails.logger.info("Removed network #{id} from cluster #{@cluster.name}")
        { success: true }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to remove network #{id}: #{e.message}")
        { success: false, error: e.message }
      end
    end
  end
end
