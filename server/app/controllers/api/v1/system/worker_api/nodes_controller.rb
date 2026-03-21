# frozen_string_literal: true

module Api
  module V1
    module System
      module WorkerApi
        # Node management for infrastructure workers
        # Provides node data and SSH key updates
        class NodesController < BaseController
          before_action :set_node, only: [:show, :update, :update_ssh_keys]

          # GET /api/v1/system/worker_api/nodes
          # List nodes managed by this worker
          def index
            authorize_worker_permission!("system.nodes.read")

            nodes = ::System::Node.where(worker: current_worker)
            nodes = apply_filters(nodes)
            nodes = paginate(nodes.includes(:node_template, :node_instances))

            render_success(
              nodes: nodes.map { |n| serialize_node(n) },
              meta: pagination_meta
            )
          end

          # GET /api/v1/system/worker_api/nodes/:id
          # Get single node with full details
          def show
            authorize_worker_permission!("system.nodes.read")

            render_success(
              node: serialize_node_full(@node)
            )
          end

          # PUT /api/v1/system/worker_api/nodes/:id
          # Update node attributes
          def update
            authorize_worker_permission!("system.nodes.update")

            if @node.update(node_params)
              render_success(node: serialize_node(@node))
            else
              render_validation_error(@node)
            end
          end

          # PUT /api/v1/system/worker_api/nodes/:id/ssh_keys
          # Update SSH keys for a node
          def update_ssh_keys
            authorize_worker_permission!("system.nodes.update")

            if @node.update(ssh_key_params)
              render_success(
                node: {
                  id: @node.id,
                  ssh_key_updated: @node.ssh_key.present?,
                  ssh_host_key_updated: @node.ssh_host_key.present?
                }
              )
            else
              render_validation_error(@node)
            end
          end

          private

          def set_node
            @node = ::System::Node.where(worker: current_worker).find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("Node")
          end

          def node_params
            params.require(:node).permit(:enabled, config: {})
          end

          def ssh_key_params
            params.require(:node).permit(:ssh_key, :ssh_host_key)
          end

          def apply_filters(scope)
            scope = scope.enabled if params[:enabled] == "true"
            scope = scope.disabled if params[:enabled] == "false"
            scope = scope.where(node_template_id: params[:template_id]) if params[:template_id].present?
            scope.ordered
          end

          def serialize_node(node)
            {
              id: node.id,
              name: node.name,
              enabled: node.enabled,
              template_id: node.node_template_id,
              instance_count: node.node_instances.count,
              allocate_public_ip: node.allocate_public_ip,
              created_at: node.created_at,
              updated_at: node.updated_at
            }
          end

          def serialize_node_full(node)
            serialize_node(node).merge(
              template: {
                id: node.node_template.id,
                name: node.node_template.name,
                platform_id: node.node_template.node_platform_id
              },
              ssh_key_present: node.ssh_key.present?,
              ssh_host_key_present: node.ssh_host_key.present?,
              config: node.config,
              instances: node.node_instances.map { |i| serialize_instance_summary(i) }
            )
          end

          def serialize_instance_summary(instance)
            {
              id: instance.id,
              name: instance.name,
              variety: instance.variety,
              status: instance.status,
              private_ip: instance.private_ip_address,
              public_ip: instance.public_ip_address
            }
          end
        end
      end
    end
  end
end
