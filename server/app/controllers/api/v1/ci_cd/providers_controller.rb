# frozen_string_literal: true

module Api
  module V1
    module CiCd
      class ProvidersController < ApplicationController
        include AuditLogging

        before_action :authenticate_request
        before_action :require_read_permission, only: [:index, :show, :test_connection]
        before_action :require_write_permission, only: [:create, :update, :destroy, :sync_repositories]
        before_action :set_provider, only: [:show, :update, :destroy, :test_connection, :sync_repositories]

        # GET /api/v1/ci_cd/providers
        def index
          providers = current_user.account.ci_cd_providers.order(created_at: :desc)

          # Filter by provider_type if provided
          providers = providers.where(provider_type: params[:provider_type]) if params[:provider_type].present?

          # Filter by active status if provided
          providers = providers.where(is_active: params[:is_active]) if params[:is_active].present?

          render_success({
            providers: serialize_collection(providers),
            meta: {
              total: providers.count,
              by_type: current_user.account.ci_cd_providers.group(:provider_type).count
            }
          })

          log_audit_event("ci_cd.providers.list", current_user.account)
        rescue StandardError => e
          Rails.logger.error "Failed to list CI/CD providers: #{e.message}"
          render_error("Failed to list providers", status: :internal_server_error)
        end

        # GET /api/v1/ci_cd/providers/:id
        def show
          render_success({
            provider: serialize_provider(@provider, include_repositories: params[:include_repositories])
          })

          log_audit_event("ci_cd.providers.read", @provider)
        rescue StandardError => e
          Rails.logger.error "Failed to get CI/CD provider: #{e.message}"
          render_error("Failed to get provider", status: :internal_server_error)
        end

        # POST /api/v1/ci_cd/providers
        def create
          provider = current_user.account.ci_cd_providers.new(provider_params)

          if provider.save
            render_success({
              provider: serialize_provider(provider),
              message: "Provider created successfully"
            }, status: :created)

            log_audit_event("ci_cd.providers.create", provider)
          else
            render_validation_error(provider.errors)
          end
        rescue StandardError => e
          Rails.logger.error "Failed to create CI/CD provider: #{e.message}"
          render_error("Failed to create provider", status: :internal_server_error)
        end

        # PATCH/PUT /api/v1/ci_cd/providers/:id
        def update
          if @provider.update(provider_params)
            render_success({
              provider: serialize_provider(@provider),
              message: "Provider updated successfully"
            })

            log_audit_event("ci_cd.providers.update", @provider)
          else
            render_validation_error(@provider.errors)
          end
        rescue StandardError => e
          Rails.logger.error "Failed to update CI/CD provider: #{e.message}"
          render_error("Failed to update provider", status: :internal_server_error)
        end

        # DELETE /api/v1/ci_cd/providers/:id
        def destroy
          @provider.destroy!

          render_success({
            message: "Provider deleted successfully"
          })

          log_audit_event("ci_cd.providers.delete", @provider)
        rescue StandardError => e
          Rails.logger.error "Failed to delete CI/CD provider: #{e.message}"
          render_error("Failed to delete provider", status: :internal_server_error)
        end

        # POST /api/v1/ci_cd/providers/:id/test_connection
        def test_connection
          result = @provider.test_connection

          render_success({
            provider_id: @provider.id,
            connected: result[:success],
            message: result[:message],
            details: result[:details],
            tested_at: Time.current
          })

          log_audit_event("ci_cd.providers.test_connection", @provider)
        rescue StandardError => e
          Rails.logger.error "Failed to test connection: #{e.message}"
          render_error("Failed to test connection: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ci_cd/providers/:id/sync_repositories
        def sync_repositories
          # Trigger async sync job via worker service
          begin
            WorkerJobService.enqueue_job(
              "CiCd::ProviderSyncJob",
              args: [@provider.id],
              queue: "ci_cd_default"
            )
            job_queued = true
          rescue WorkerJobService::WorkerServiceError => e
            Rails.logger.warn "Worker service unavailable for sync: #{e.message}"
            job_queued = false
          end

          render_success({
            provider_id: @provider.id,
            message: job_queued ? "Repository sync initiated" : "Sync request received but worker unavailable",
            sync_started_at: Time.current,
            job_queued: job_queued
          })

          log_audit_event("ci_cd.providers.sync_repositories", @provider)
        rescue StandardError => e
          Rails.logger.error "Failed to sync repositories: #{e.message}"
          render_error("Failed to sync repositories: #{e.message}", status: :unprocessable_content)
        end

        private

        def set_provider
          @provider = current_user.account.ci_cd_providers.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Provider not found", status: :not_found)
        end

        def require_read_permission
          return if current_user.has_permission?("ci_cd.providers.read")

          render_error("Insufficient permissions to view CI/CD providers", status: :forbidden)
        end

        def require_write_permission
          return if current_user.has_permission?("ci_cd.providers.write")

          render_error("Insufficient permissions to manage CI/CD providers", status: :forbidden)
        end

        def provider_params
          params.require(:provider).permit(
            :name,
            :provider_type,
            :base_url,
            :api_token,
            :webhook_secret,
            :is_active,
            settings: {}
          )
        end

        def serialize_collection(providers)
          providers.map { |p| serialize_provider(p) }
        end

        def serialize_provider(provider, include_repositories: false)
          result = ::CiCd::ProviderSerializer.new(provider).serializable_hash[:data][:attributes]
          result[:id] = provider.id

          if include_repositories == "true" || include_repositories == true
            result[:repositories] = provider.repositories.map do |repo|
              ::CiCd::RepositorySerializer.new(repo).serializable_hash[:data][:attributes].merge(id: repo.id)
            end
          end

          result
        end
      end
    end
  end
end
