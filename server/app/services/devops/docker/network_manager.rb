# frozen_string_literal: true

module Devops
  module Docker
    class NetworkManager
      def initialize(cluster:)
        @cluster = cluster
        @client = ApiClient.new(cluster)
      end

      def list
        @client.network_list.map { |n| serialize_network(n) }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to list networks for cluster #{@cluster.name}: #{e.message}")
        raise
      end

      def inspect_network(id)
        serialize_network_detail(@client.network_inspect(id))
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

      private

      def serialize_network(data)
        {
          id: data["Id"],
          name: data["Name"],
          driver: data["Driver"],
          scope: data["Scope"],
          internal: data["Internal"] || false,
          attachable: data["Attachable"] || false,
          ingress: data["Ingress"] || false,
          labels: data["Labels"] || {},
          created_at: data["Created"]
        }
      end

      def serialize_network_detail(data)
        ipam = data["IPAM"] || {}
        containers = data["Containers"] || {}

        serialize_network(data).merge(
          ipam_driver: ipam["Driver"],
          ipam_config: (ipam["Config"] || []).map { |c|
            {
              subnet: c["Subnet"],
              gateway: c["Gateway"],
              ip_range: c["IPRange"],
              aux_addresses: c["AuxiliaryAddresses"] || {}
            }
          },
          containers: containers.map { |id, c|
            {
              id: id,
              name: c["Name"],
              ipv4_address: c["IPv4Address"] || "",
              ipv6_address: c["IPv6Address"] || "",
              mac_address: c["MacAddress"] || ""
            }
          },
          options: data["Options"] || {},
          enable_ipv6: data["EnableIPv6"] || false,
          peers: (data["Peers"] || []).map { |p| { name: p["Name"], ip: p["IP"] } }
        )
      end
    end
  end
end
