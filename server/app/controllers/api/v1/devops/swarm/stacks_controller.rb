# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Swarm
        class StacksController < ApplicationController
          include AuditLogging

          before_action :set_cluster
          before_action :set_stack, only: %i[show update destroy deploy remove_stack]

          # GET /api/v1/devops/swarm/clusters/:cluster_id/stacks
          def index
            scope = @cluster.swarm_stacks

            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.order(name: :asc)

            render_success(items: scope.map(&:stack_summary))
          end

          # GET /api/v1/devops/swarm/clusters/:cluster_id/stacks/:id
          def show
            render_success(stack: @stack.stack_details)
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/stacks
          def create
            stack = @cluster.swarm_stacks.build(stack_params)

            if stack.save
              render_success({ stack: stack.stack_details }, status: :created)
              log_audit_event("swarm.stacks.create", stack)
            else
              render_error(stack.errors.full_messages.join(", "), status: :unprocessable_entity)
            end
          end

          # PATCH /api/v1/devops/swarm/clusters/:cluster_id/stacks/:id
          def update
            if @stack.update(stack_params)
              render_success(stack: @stack.stack_details)
              log_audit_event("swarm.stacks.update", @stack)
            else
              render_error(@stack.errors.full_messages.join(", "), status: :unprocessable_entity)
            end
          end

          # DELETE /api/v1/devops/swarm/clusters/:cluster_id/stacks/:id
          def destroy
            @stack.destroy!
            render_success(message: "Stack deleted successfully")
            log_audit_event("swarm.stacks.delete", @stack)
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/stacks/:id/deploy
          def deploy
            manager = ::Devops::Docker::StackManager.new(cluster: @cluster, user: current_user)

            begin
              manager.deploy_stack(@stack)
              render_success(stack: @stack.reload.stack_details)
              log_audit_event("swarm.stacks.deploy", @stack)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Deploy failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/stacks/:id/remove_stack
          def remove_stack
            manager = ::Devops::Docker::StackManager.new(cluster: @cluster, user: current_user)

            begin
              manager.remove_stack(@stack)
              render_success(stack: @stack.reload.stack_details)
              log_audit_event("swarm.stacks.remove", @stack)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Stack removal failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          private

          def set_cluster
            @cluster = current_user.account.devops_swarm_clusters.find(params[:cluster_id])
          end

          def set_stack
            @stack = @cluster.swarm_stacks.find(params[:id])
          end

          def stack_params
            params.require(:stack).permit(:name, :compose_file, compose_variables: {})
          end
        end
      end
    end
  end
end
