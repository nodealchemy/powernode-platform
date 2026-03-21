# frozen_string_literal: true

module Api
  module V1
    module System
      class NodesController < BaseController
        before_action :set_account
        before_action :set_node, only: [:show, :update, :destroy]

        def index
          authorize_permission!("system.nodes.read")
          nodes = @account.system_nodes.includes(:node_template, :worker)
          nodes = apply_filters(nodes)
          nodes = paginate(nodes)
          render_success(nodes: serialize_collection(nodes), meta: pagination_meta)
        end

        def show
          authorize_permission!("system.nodes.read")
          render_success(node: serialize_node(@node))
        end

        def create
          authorize_permission!("system.nodes.create")
          node = @account.system_nodes.build(node_params)

          if node.save
            render_success(node: serialize_node(node), status: :created)
          else
            render_validation_error(node)
          end
        end

        def update
          authorize_permission!("system.nodes.update")

          if @node.update(node_params)
            render_success(node: serialize_node(@node))
          else
            render_validation_error(@node)
          end
        end

        def destroy
          authorize_permission!("system.nodes.delete")

          if @node.destroy
            render_success(message: "Node deleted successfully")
          else
            render_error("Failed to delete node", status: :unprocessable_entity)
          end
        end

        private

        def set_node
          @node = @account.system_nodes.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Node")
        end

        def node_params
          params.require(:node).permit(
            :name, :description, :enabled, :node_template_id, :worker_id,
            :public_address, :allocate_public_ip, :ssh_key, :ssh_host_key,
            config: {}
          )
        end

        def apply_filters(scope)
          scope = scope.enabled if params[:enabled] == "true"
          scope = scope.disabled if params[:enabled] == "false"
          scope = scope.where(node_template_id: params[:template_id]) if params[:template_id].present?
          scope.ordered
        end

        def serialize_node(node)
          ::System::NodeSerializer.new(node).as_json
        end

        def serialize_collection(nodes)
          nodes.map { |n| serialize_node(n) }
        end
      end
    end
  end
end
