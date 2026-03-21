# frozen_string_literal: true

module System
  module Providers
    # Registry for cloud provider adapters
    # Provides factory methods for creating provider instances based on connection type
    class Registry
      class UnknownProviderError < StandardError; end

      # Registered provider types and their adapter classes
      # Provider classes are loaded lazily to avoid loading unnecessary dependencies
      PROVIDER_CLASSES = {
        "aws" => "System::Providers::AwsProvider",
        "gcp" => "System::Providers::GcpProvider",
        "azure" => "System::Providers::AzureProvider",
        "openstack" => "System::Providers::OpenStackProvider",
        "mock" => "System::Providers::MockProvider"
      }.freeze

      class << self
        # Get a provider adapter for a connection
        #
        # @param connection [System::ProviderConnection] The provider connection
        # @param region [System::ProviderRegion, nil] Optional region override
        # @return [BaseProvider] The provider adapter instance
        # @raise [UnknownProviderError] If provider type is not registered
        def for(connection, region: nil)
          provider_type = connection.provider.provider_type

          unless PROVIDER_CLASSES.key?(provider_type)
            raise UnknownProviderError, "Unknown provider type: #{provider_type}. " \
                                        "Available: #{available_providers.join(', ')}"
          end

          provider_class = PROVIDER_CLASSES[provider_type].constantize
          provider_class.new(connection, region: region)
        end

        # Get a provider adapter for a node instance
        #
        # @param instance [System::NodeInstance] The node instance
        # @return [BaseProvider] The provider adapter instance
        # @raise [UnknownProviderError] If no connection found or provider unknown
        def for_instance(instance)
          connection = find_connection_for_instance(instance)

          unless connection
            raise UnknownProviderError, "No provider connection available for instance #{instance.id}"
          end

          self.for(connection, region: instance.provider_region)
        end

        # Get a provider adapter for a node
        #
        # @param node [System::Node] The node
        # @param region [System::ProviderRegion] The target region
        # @return [BaseProvider] The provider adapter instance
        def for_node(node, region:)
          connection = find_connection_for_region(region, node.account)

          unless connection
            raise UnknownProviderError, "No provider connection available for region #{region.id}"
          end

          self.for(connection, region: region)
        end

        # Get a provider adapter for a volume
        #
        # @param volume [System::ProviderVolume] The volume
        # @return [BaseProvider] The provider adapter instance
        def for_volume(volume)
          connection = find_connection_for_region(volume.provider_region, volume.account)

          unless connection
            raise UnknownProviderError, "No provider connection available for volume #{volume.id}"
          end

          self.for(connection, region: volume.provider_region)
        end

        # List available provider types
        #
        # @return [Array<String>] Available provider type identifiers
        def available_providers
          PROVIDER_CLASSES.keys
        end

        # Check if a provider type is supported
        #
        # @param provider_type [String] The provider type to check
        # @return [Boolean] True if provider is supported
        def supported?(provider_type)
          PROVIDER_CLASSES.key?(provider_type)
        end

        # Register a custom provider (for extensions/plugins)
        #
        # @param provider_type [String] The provider type identifier
        # @param class_name [String] The fully qualified class name
        def register(provider_type, class_name)
          PROVIDER_CLASSES[provider_type] = class_name
        end

        private

        # Find a suitable connection for an instance
        #
        # @param instance [System::NodeInstance] The instance
        # @return [System::ProviderConnection, nil] The connection or nil
        def find_connection_for_instance(instance)
          region = instance.provider_region
          return nil unless region

          find_connection_for_region(region, instance.node&.account)
        end

        # Find a suitable connection for a region and account
        #
        # @param region [System::ProviderRegion] The region
        # @param account [Account] The account
        # @return [System::ProviderConnection, nil] The connection or nil
        def find_connection_for_region(region, account)
          provider = region.provider

          ::System::ProviderConnection
            .where(provider: provider)
            .where("account_id = ? OR account_id IS NULL", account&.id)
            .where(status: "connected")
            .order(Arel.sql("CASE WHEN account_id IS NOT NULL THEN 0 ELSE 1 END"))
            .first
        end
      end
    end
  end
end
