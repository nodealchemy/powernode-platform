# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Swarm
        class DeploymentsController < ApplicationController
          include AuditLogging

          before_action :set_cluster

          # GET /api/v1/devops/swarm/clusters/:cluster_id/deployments
          def index
            scope = @cluster.swarm_deployments

            scope = scope.by_type(params[:deployment_type]) if params[:deployment_type].present?
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.for_service(params[:service_id]) if params[:service_id].present?
            scope = scope.for_stack(params[:stack_id]) if params[:stack_id].present?

            if params[:since].present?
              scope = scope.where("created_at >= ?", Time.zone.parse(params[:since]))
            end

            scope = scope.recent

            render_success(items: scope.limit(params[:limit]&.to_i || 50).map(&:deployment_summary))
          end

          # GET /api/v1/devops/swarm/clusters/:cluster_id/deployments/:id
          def show
            deployment = @cluster.swarm_deployments.find(params[:id])
            render_success(deployment: deployment.deployment_details)
          end

          private

          def set_cluster
            @cluster = current_user.account.devops_swarm_clusters.find(params[:cluster_id])
          end
        end
      end
    end
  end
end
