# frozen_string_literal: true

module Api
  module V1
    module Devops
      class RepositoriesController < ApplicationController
        include AuditLogging

        before_action :authenticate_request
        before_action :require_read_permission, only: [ :index, :show ]
        before_action :require_write_permission, only: [ :create, :update, :destroy, :sync, :attach_pipeline, :detach_pipeline ]
        before_action :set_repository, only: [ :show, :update, :destroy, :sync, :attach_pipeline, :detach_pipeline ]

        # GET /api/v1/devops/repositories
        def index
          repositories = current_user.account.devops_repositories
                                     .includes(:provider, :pipelines)
                                     .order(created_at: :desc)

          # Filter by provider if provided
          repositories = repositories.where(devops_provider_id: params[:provider_id]) if params[:provider_id].present?

          # Filter by active status if provided
          repositories = repositories.where(is_active: params[:is_active]) if params[:is_active].present?

          render_success({
            repositories: serialize_collection(repositories),
            meta: {
              total: repositories.count,
              active_count: current_user.account.devops_repositories.where(is_active: true).count,
              by_provider: current_user.account.devops_repositories.group(:devops_provider_id).count
            }
          })

          log_audit_event("devops.repositories.list", current_user.account)
        rescue StandardError => e
          Rails.logger.error "Failed to list repositories: #{e.message}"
          render_error("Failed to list repositories", status: :internal_server_error)
        end

        # GET /api/v1/devops/repositories/:id
        def show
          render_success({
            repository: serialize_repository(@repository, include_pipelines: params[:include_pipelines])
          })

          log_audit_event("devops.repositories.read", @repository)
        rescue StandardError => e
          Rails.logger.error "Failed to get repository: #{e.message}"
          render_error("Failed to get repository", status: :internal_server_error)
        end

        # POST /api/v1/devops/repositories
        def create
          # Verify provider belongs to account
          provider = current_user.account.devops_providers.find(params[:repository][:provider_id])

          repository = current_user.account.devops_repositories.new(repository_params)
          repository.provider = provider

          if repository.save
            render_success({
              repository: serialize_repository(repository),
              message: "Repository created successfully"
            }, status: :created)

            log_audit_event("devops.repositories.create", repository)
          else
            render_validation_error(repository.errors)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Provider not found", status: :not_found)
        rescue StandardError => e
          Rails.logger.error "Failed to create repository: #{e.message}"
          render_error("Failed to create repository", status: :internal_server_error)
        end

        # PATCH/PUT /api/v1/devops/repositories/:id
        def update
          # If changing provider, verify it belongs to the account
          if params[:repository][:provider_id].present?
            current_user.account.devops_providers.find(params[:repository][:provider_id])
          end

          if @repository.update(repository_params)
            render_success({
              repository: serialize_repository(@repository),
              message: "Repository updated successfully"
            })

            log_audit_event("devops.repositories.update", @repository)
          else
            render_validation_error(@repository.errors)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Provider not found", status: :not_found)
        rescue StandardError => e
          Rails.logger.error "Failed to update repository: #{e.message}"
          render_error("Failed to update repository", status: :internal_server_error)
        end

        # DELETE /api/v1/devops/repositories/:id
        def destroy
          @repository.destroy!

          render_success({
            message: "Repository deleted successfully"
          })

          log_audit_event("devops.repositories.delete", @repository)
        rescue StandardError => e
          Rails.logger.error "Failed to delete repository: #{e.message}"
          render_error("Failed to delete repository", status: :internal_server_error)
        end

        # POST /api/v1/devops/repositories/:id/sync
        def sync
          @repository.update!(last_synced_at: Time.current)

          # Trigger async sync job via worker service
          begin
            WorkerJobService.enqueue_job(
              "Devops::ProviderSyncJob",
              args: [ @repository.devops_provider_id, { repository_id: @repository.id } ],
              queue: "devops_default"
            )
            job_queued = true
          rescue WorkerJobService::WorkerServiceError => e
            Rails.logger.warn "Worker service unavailable for repository sync: #{e.message}"
            job_queued = false
          end

          render_success({
            repository_id: @repository.id,
            message: job_queued ? "Repository sync initiated" : "Sync request received but worker unavailable",
            sync_started_at: Time.current,
            job_queued: job_queued
          })

          log_audit_event("devops.repositories.sync", @repository)
        rescue StandardError => e
          render_internal_error("Failed to sync repository", exception: e)
        end

        # POST /api/v1/devops/repositories/:id/attach_pipeline
        def attach_pipeline
          pipeline = current_user.account.devops_pipelines.find(params[:pipeline_id])

          # Check if already attached
          if @repository.pipeline_repositories.exists?(ci_cd_pipeline_id: pipeline.id)
            render_error("Pipeline already attached to this repository", status: :unprocessable_content)
            return
          end

          pipeline_repo = @repository.pipeline_repositories.create!(
            pipeline: pipeline,
            overrides: params[:overrides] || {}
          )

          render_success({
            repository: serialize_repository(@repository, include_pipelines: true),
            attached_pipeline: {
              id: pipeline.id,
              name: pipeline.name,
              overrides: pipeline_repo.overrides
            },
            message: "Pipeline attached successfully"
          })

          log_audit_event("devops.repositories.attach_pipeline", @repository)
        rescue ActiveRecord::RecordNotFound
          render_error("Pipeline not found", status: :not_found)
        rescue StandardError => e
          render_internal_error("Failed to attach pipeline", exception: e)
        end

        # DELETE /api/v1/devops/repositories/:id/detach_pipeline
        def detach_pipeline
          pipeline_repo = @repository.pipeline_repositories.find_by!(ci_cd_pipeline_id: params[:pipeline_id])
          pipeline_repo.destroy!

          render_success({
            repository: serialize_repository(@repository, include_pipelines: true),
            message: "Pipeline detached successfully"
          })

          log_audit_event("devops.repositories.detach_pipeline", @repository)
        rescue ActiveRecord::RecordNotFound
          render_error("Pipeline not attached to this repository", status: :not_found)
        rescue StandardError => e
          render_internal_error("Failed to detach pipeline", exception: e)
        end

        private

        def set_repository
          @repository = current_user.account.devops_repositories.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Repository not found", status: :not_found)
        end

        def require_read_permission
          return if current_user.has_permission?("devops.repositories.read")

          render_error("Insufficient permissions to view repositories", status: :forbidden)
        end

        def require_write_permission
          return if current_user.has_permission?("devops.repositories.write")

          render_error("Insufficient permissions to manage repositories", status: :forbidden)
        end

        def repository_params
          params.require(:repository).permit(
            :name,
            :full_name,
            :default_branch,
            :external_id,
            :is_active,
            :provider_id,
            settings: {}
          )
        end

        def serialize_collection(repositories)
          repositories.map { |r| serialize_repository(r) }
        end

        def serialize_repository(repository, include_pipelines: false)
          result = ::Devops::RepositorySerializer.new(repository).serializable_hash[:data][:attributes]
          result[:id] = repository.id

          if include_pipelines == "true" || include_pipelines == true
            result[:pipelines] = repository.pipeline_repositories.includes(:pipeline).map do |pr|
              {
                id: pr.pipeline.id,
                name: pr.pipeline.name,
                slug: pr.pipeline.slug,
                overrides: pr.overrides,
                attached_at: pr.created_at
              }
            end
          end

          result
        end
      end
    end
  end
end
