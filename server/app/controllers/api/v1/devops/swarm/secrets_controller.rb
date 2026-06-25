# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Swarm
        class SecretsController < ApplicationController
          include AuditLogging

          # Authorization on the dedicated swarm family. Swarm secrets are
          # sensitive credential material: reads (metadata only — Docker never
          # returns secret values) gate on devops.swarm.read; create/destroy on
          # devops.swarm.manage. Without these gates any authenticated user could
          # list/create/delete Swarm secrets.
          before_action :require_secrets_read, only: %i[index show]
          before_action :require_secrets_manage, only: %i[create destroy]
          before_action :set_cluster

          # GET /api/v1/devops/swarm/clusters/:cluster_id/secrets
          def index
            manager = ::Devops::Docker::SecretManager.new(cluster: @cluster)

            begin
              secrets = manager.list
              render_success(items: secrets)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to list secrets: #{e.message}", status: :unprocessable_content)
            end
          end

          # GET /api/v1/devops/swarm/clusters/:cluster_id/secrets/:id
          def show
            manager = ::Devops::Docker::SecretManager.new(cluster: @cluster)

            begin
              secret = manager.inspect_secret(params[:id])
              render_success(secret: secret)
            rescue ::Devops::Docker::ApiClient::NotFoundError
              render_error("Secret not found", status: :not_found)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to inspect secret: #{e.message}", status: :unprocessable_content)
            end
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/secrets
          def create
            manager = ::Devops::Docker::SecretManager.new(cluster: @cluster)

            begin
              secret = manager.create(secret_params)
              render_success({ secret: secret }, status: :created)
              log_audit_event("swarm.secrets.create", @cluster)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to create secret: #{e.message}", status: :unprocessable_content)
            end
          end

          # DELETE /api/v1/devops/swarm/clusters/:cluster_id/secrets/:id
          def destroy
            manager = ::Devops::Docker::SecretManager.new(cluster: @cluster)

            begin
              manager.remove(params[:id])
              render_success(message: "Secret removed successfully")
              log_audit_event("swarm.secrets.delete", @cluster)
            rescue ::Devops::Docker::ApiClient::NotFoundError
              render_error("Secret not found", status: :not_found)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to remove secret: #{e.message}", status: :unprocessable_content)
            end
          end

          private

          def require_secrets_read
            require_permission("devops.swarm.read")
          end

          def require_secrets_manage
            require_permission("devops.swarm.manage")
          end

          def set_cluster
            @cluster = current_user.account.devops_swarm_clusters.find(params[:cluster_id])
          end

          def secret_params
            params.require(:secret).permit(:name, :data, labels: {})
          end
        end
      end
    end
  end
end
