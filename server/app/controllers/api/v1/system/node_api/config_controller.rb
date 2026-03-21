# frozen_string_literal: true

module Api
  module V1
    module System
      module NodeApi
        # Instance configuration endpoint
        # Provides instance with its configuration data
        class ConfigController < BaseController
          # GET /api/v1/system/node_api/config
          # Returns instance configuration
          def show
            render_success(
              instance: serialize_instance,
              node: serialize_node,
              template: serialize_template,
              architecture: serialize_architecture
            )
          end

          # GET /api/v1/system/node_api/config/authorized_keys
          # Returns SSH authorized keys for the instance
          def authorized_keys
            keys = []

            # Add node's SSH public key
            if current_node.ssh_key.present?
              keys << extract_public_key(current_node.ssh_key)
            end

            # Add any additional authorized keys from config
            if current_node.config&.dig("authorized_keys").present?
              keys.concat(Array(current_node.config["authorized_keys"]))
            end

            render_success(
              authorized_keys: keys.compact.join("\n"),
              keys_count: keys.compact.length
            )
          end

          # GET /api/v1/system/node_api/config/host_keys
          # Returns SSH host keys for the instance
          def host_keys
            host_keys = {}

            # Add node's host key if present
            if current_node.ssh_host_key.present?
              host_keys[:default] = current_node.ssh_host_key
            end

            # Add instance-specific host keys from config
            if current_instance.config&.dig("host_keys").present?
              host_keys.merge!(current_instance.config["host_keys"])
            end

            render_success(host_keys: host_keys)
          end

          # GET /api/v1/system/node_api/config/network
          # Returns network configuration for the instance
          def network
            render_success(
              private_ip_address: current_instance.private_ip_address,
              public_ip_address: current_instance.public_ip_address,
              allocate_public_ip: current_node.allocate_public_ip,
              provider_region: serialize_provider_region
            )
          end

          private

          def serialize_instance
            {
              id: current_instance.id,
              name: current_instance.name,
              variety: current_instance.variety,
              status: current_instance.status,
              private_ip_address: current_instance.private_ip_address,
              public_ip_address: current_instance.public_ip_address,
              cloud_instance_id: current_instance.cloud_instance_id,
              config: current_instance.config
            }
          end

          def serialize_node
            {
              id: current_node.id,
              name: current_node.name,
              allocate_public_ip: current_node.allocate_public_ip,
              config: current_node.config
            }
          end

          def serialize_template
            return nil unless current_template

            {
              id: current_template.id,
              name: current_template.name,
              platform_id: current_template.node_platform_id,
              architecture_id: current_template.node_architecture_id,
              config: current_template.config
            }
          end

          def serialize_architecture
            return nil unless current_template&.node_architecture

            arch = current_template.node_architecture
            {
              id: arch.id,
              name: arch.name,
              config: arch.respond_to?(:config) ? arch.config : nil
            }
          end

          def serialize_provider_region
            return nil unless current_instance.provider_region

            region = current_instance.provider_region
            {
              id: region.id,
              name: region.name,
              region_code: region.region_code
            }
          end

          def extract_public_key(key_pair)
            # If key_pair is JSON with private/public, extract public
            return nil if key_pair.blank?

            begin
              parsed = JSON.parse(key_pair)
              parsed["public_key"] || parsed["public"]
            rescue JSON::ParserError
              # Assume it's a raw public key
              key_pair if key_pair.start_with?("ssh-")
            end
          end
        end
      end
    end
  end
end
