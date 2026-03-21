# frozen_string_literal: true

module Api
  module V1
    module Internal
      module System
        # Internal API controller for system node operations
        class NodesController < BaseController
          before_action :set_node, only: %i[show instances provision maintenance]

          # GET /api/v1/internal/system/nodes
          def index
            nodes = ::System::Node.all

            nodes = nodes.where(enabled: true) if params[:enabled].present?
            nodes = nodes.where(account_id: params[:account_id]) if params[:account_id].present?

            if params[:has_cloud_instances].present?
              nodes = nodes.joins(:node_instances)
                           .where(system_node_instances: { variety: %w[cloud dynamic] })
                           .distinct
            end

            nodes = nodes.includes(:node_template, :node_instances)
                         .limit(params[:limit] || 100)

            render_success(
              data: {
                nodes: nodes.map { |n| node_data(n) }
              }
            )
          end

          # GET /api/v1/internal/system/nodes/:id
          def show
            render_success(data: node_data(@node))
          end

          # GET /api/v1/internal/system/nodes/:id/instances
          def instances
            instances = @node.node_instances

            if params[:variety].present?
              varieties = Array(params[:variety])
              instances = instances.where(variety: varieties)
            end

            instances = instances.where(status: params[:status]) if params[:status].present?

            render_success(
              data: {
                node_instances: instances.map { |i| instance_data(i) }
              }
            )
          end

          # POST /api/v1/internal/system/nodes/:id/provision
          # Provision a new cloud instance for this node
          def provision
            operation_id = params[:operation_id]

            # Validate node can provision
            unless @node.enabled
              return render_error("Node is disabled", status: :unprocessable_entity)
            end

            # Check instance limits
            account = @node.account
            if account.instance_limit_reached?
              return render_error("Account instance limit reached", status: :unprocessable_entity)
            end

            # Get provisioning parameters
            region_id = params[:provider_region_id]
            instance_type_id = params[:provider_instance_type_id]

            # Create the instance via provisioning service
            result = ::System::ProvisioningService.provision_instance(
              node: @node,
              provider_region_id: region_id,
              provider_instance_type_id: instance_type_id,
              operation_id: operation_id,
              options: params[:options] || {}
            )

            if result[:success]
              render_success(
                data: {
                  success: true,
                  node_instance: instance_data(result[:instance]),
                  cloud_instance_id: result[:cloud_instance_id]
                }
              )
            else
              render_error(result[:error], status: :unprocessable_entity)
            end
          rescue StandardError => e
            Rails.logger.error("[System::NodesController] Provision failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          # POST /api/v1/internal/system/nodes/:id/maintenance
          # Run maintenance on node
          def maintenance
            operation_id = params[:operation_id]

            result = ::System::NodeMaintenanceService.run_maintenance(
              node: @node,
              operation_id: operation_id
            )

            render_success(
              data: {
                success: result[:success],
                instances_maintained: result[:instances_maintained],
                errors: result[:errors]
              }
            )
          rescue StandardError => e
            Rails.logger.error("[System::NodesController] Maintenance failed: #{e.message}")
            render_error(e.message, status: :internal_server_error)
          end

          private

          def set_node
            @node = ::System::Node.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_not_found("Node")
          end

          def node_data(node)
            {
              id: node.id,
              name: node.name,
              description: node.description,
              enabled: node.enabled,
              account_id: node.account_id,
              node_template_id: node.node_template_id,
              ssh_key: node.ssh_key.present?,
              ssh_host_key: node.ssh_host_key.present?,
              public_address: node.public_address,
              allocate_public_ip: node.allocate_public_ip,
              config: node.config,
              instance_count: node.node_instances.size,
              last_ssh_check_failed: node.last_ssh_check_failed,
              state_stale: node.state_stale?,
              created_at: node.created_at,
              updated_at: node.updated_at
            }
          end

          def instance_data(instance)
            {
              id: instance.id,
              name: instance.name,
              variety: instance.variety,
              status: instance.status,
              node_id: instance.node_id,
              private_ip_address: instance.private_ip_address,
              public_ip_address: instance.public_ip_address,
              provider_region_id: instance.provider_region_id,
              provider_instance_type_id: instance.provider_instance_type_id,
              cloud_instance_id: instance.cloud_instance_id,
              admin_user: instance.admin_user,
              last_synced_at: instance.last_synced_at,
              created_at: instance.created_at,
              updated_at: instance.updated_at
            }
          end
        end
      end
    end
  end
end
