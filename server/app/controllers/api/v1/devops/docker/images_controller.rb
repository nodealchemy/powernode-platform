# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Docker
        class ImagesController < ApplicationController
          include AuditLogging

          before_action :set_host
          before_action :set_image, only: %i[show destroy tag]

          # GET /api/v1/devops/docker/hosts/:host_id/images
          def index
            scope = @host.docker_images

            scope = scope.dangling if params[:dangling] == "true"
            scope = scope.tagged if params[:dangling] == "false"
            scope = scope.order(created_at: :desc)

            render_success(items: scope.map(&:image_summary))
          end

          # GET /api/v1/devops/docker/hosts/:host_id/images/available
          def available
            manager = ::Devops::Docker::HostManager.new(account: current_user.account)

            begin
              images = manager.available_images(@host)
              render_success(items: images)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to fetch available images: #{e.message}", status: :unprocessable_entity)
            end
          end

          # POST /api/v1/devops/docker/hosts/:host_id/images/import
          def import
            docker_image_ids = Array(params[:docker_image_ids])

            if docker_image_ids.empty?
              return render_error("No image IDs provided", status: :unprocessable_entity)
            end

            manager = ::Devops::Docker::HostManager.new(account: current_user.account)

            begin
              imported = manager.import_images(@host, docker_image_ids)
              render_success(
                items: imported.map(&:image_summary),
                imported_count: imported.size
              )
              log_audit_event("docker.images.import", @host)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Import failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          # GET /api/v1/devops/docker/hosts/:host_id/images/:id
          def show
            render_success(image: @image.image_details)
          end

          # POST /api/v1/devops/docker/hosts/:host_id/images/pull
          def pull
            manager = ::Devops::Docker::ImageManager.new(host: @host, user: current_user)

            begin
              result = manager.pull_image(
                image: params[:image],
                tag: params[:tag] || "latest",
                credential_id: params[:credential_id]
              )
              render_success(result: result)
              log_audit_event("docker.images.pull", @host)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Image pull failed: #{e.message}", status: :unprocessable_entity)
            rescue ActiveRecord::RecordNotFound
              render_error("Credential not found", status: :not_found)
            end
          end

          # DELETE /api/v1/devops/docker/hosts/:host_id/images/:id
          def destroy
            manager = ::Devops::Docker::ImageManager.new(host: @host, user: current_user)

            begin
              manager.remove_image(@image, force: params[:force] == "true")
              render_success(message: "Image removed successfully")
              log_audit_event("docker.images.delete", @host)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Image removal failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          # POST /api/v1/devops/docker/hosts/:host_id/images/:id/tag
          def tag
            manager = ::Devops::Docker::ImageManager.new(host: @host, user: current_user)

            begin
              manager.tag_image(@image, repo: params[:repo], tag: params[:tag])
              render_success(image: @image.reload.image_details)
              log_audit_event("docker.images.tag", @host)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Image tagging failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          # GET /api/v1/devops/docker/hosts/:host_id/images/registries
          def registries
            registry_service = ::Devops::Docker::RegistryService.new
            registries = registry_service.available_registries(current_user.account)

            render_success(items: registries)
          end

          private

          def set_host
            @host = current_user.account.devops_docker_hosts.find(params[:host_id])
          end

          def set_image
            @image = @host.docker_images.find(params[:id])
          end
        end
      end
    end
  end
end
