# frozen_string_literal: true

module Devops
  module Docker
    class SecretManager
      def initialize(cluster:)
        @cluster = cluster
        @client = ApiClient.new(cluster)
      end

      def list
        @client.secret_list.map { |s| serialize_secret(s) }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to list secrets for cluster #{@cluster.name}: #{e.message}")
        raise
      end

      def inspect_secret(id)
        serialize_secret(@client.secret_inspect(id))
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to inspect secret #{id}: #{e.message}")
        raise
      end

      def create(params)
        result = @client.secret_create(params)
        Rails.logger.info("Created secret #{params["Name"]} on cluster #{@cluster.name}")
        { success: true, id: result["ID"] }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to create secret: #{e.message}")
        { success: false, error: e.message }
      end

      def remove(id)
        @client.secret_delete(id)
        Rails.logger.info("Removed secret #{id} from cluster #{@cluster.name}")
        { success: true }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to remove secret #{id}: #{e.message}")
        { success: false, error: e.message }
      end

      # Config operations (configs share the same Swarm resource shape as secrets)

      def list_configs
        @client.config_list.map { |c| serialize_config(c) }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to list configs for cluster #{@cluster.name}: #{e.message}")
        raise
      end

      def inspect_config(id)
        serialize_config(@client.config_inspect(id))
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to inspect config #{id}: #{e.message}")
        raise
      end

      def create_config(params)
        result = @client.config_create(params)
        Rails.logger.info("Created config #{params["Name"]} on cluster #{@cluster.name}")
        { success: true, id: result["ID"] }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to create config: #{e.message}")
        { success: false, error: e.message }
      end

      def remove_config(id)
        @client.config_delete(id)
        Rails.logger.info("Removed config #{id} from cluster #{@cluster.name}")
        { success: true }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to remove config #{id}: #{e.message}")
        { success: false, error: e.message }
      end

      private

      def serialize_secret(data)
        {
          id: data["ID"],
          name: data.dig("Spec", "Name"),
          labels: data.dig("Spec", "Labels") || {},
          created_at: data["CreatedAt"],
          updated_at: data["UpdatedAt"]
        }
      end

      def serialize_config(data)
        {
          id: data["ID"],
          name: data.dig("Spec", "Name"),
          labels: data.dig("Spec", "Labels") || {},
          created_at: data["CreatedAt"],
          updated_at: data["UpdatedAt"]
        }
      end
    end
  end
end
