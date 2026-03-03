# frozen_string_literal: true

module Api
  module V1
    module Devops
      class ProvidersController < ApplicationController
        include AuditLogging

        before_action :authenticate_request
        before_action :require_read_permission, only: [ :index, :show, :test_connection ]
        before_action :require_write_permission, only: [ :create, :update, :destroy, :sync_repositories ]
        before_action :set_provider, only: [ :show, :update, :destroy, :test_connection, :sync_repositories ]

        # GET /api/v1/devops/providers
        def index
          providers = current_user.account.git_providers.active.ordered_by_priority

          providers = providers.where(provider_type: params[:provider_type]) if params[:provider_type].present?
          providers = providers.where(is_active: params[:is_active]) if params[:is_active].present?

          render_success({
            providers: providers.map { |p| serialize_provider(p) },
            meta: {
              total: providers.count,
              by_type: current_user.account.git_providers.group(:provider_type).count
            }
          })

          log_audit_event("devops.providers.list", current_user.account)
        rescue StandardError => e
          Rails.logger.error "Failed to list DevOps providers: #{e.message}"
          render_error("Failed to list providers", status: :internal_server_error)
        end

        # GET /api/v1/devops/providers/:id
        def show
          render_success({
            provider: serialize_provider(@provider, include_repositories: params[:include_repositories])
          })

          log_audit_event("devops.providers.read", @provider)
        rescue StandardError => e
          Rails.logger.error "Failed to get DevOps provider: #{e.message}"
          render_error("Failed to get provider", status: :internal_server_error)
        end

        # POST /api/v1/devops/providers
        def create
          provider = current_user.account.git_providers.new(provider_params)

          if provider.save
            render_success({
              provider: serialize_provider(provider),
              message: "Provider created successfully"
            }, status: :created)

            log_audit_event("devops.providers.create", provider)
          else
            render_validation_error(provider.errors)
          end
        rescue StandardError => e
          Rails.logger.error "Failed to create DevOps provider: #{e.message}"
          render_error("Failed to create provider", status: :internal_server_error)
        end

        # PATCH/PUT /api/v1/devops/providers/:id
        def update
          if @provider.update(provider_params)
            render_success({
              provider: serialize_provider(@provider),
              message: "Provider updated successfully"
            })

            log_audit_event("devops.providers.update", @provider)
          else
            render_validation_error(@provider.errors)
          end
        rescue StandardError => e
          Rails.logger.error "Failed to update DevOps provider: #{e.message}"
          render_error("Failed to update provider", status: :internal_server_error)
        end

        # DELETE /api/v1/devops/providers/:id
        def destroy
          @provider.destroy!

          render_success({
            message: "Provider deleted successfully"
          })

          log_audit_event("devops.providers.delete", @provider)
        rescue StandardError => e
          Rails.logger.error "Failed to delete DevOps provider: #{e.message}"
          render_error("Failed to delete provider", status: :internal_server_error)
        end

        # POST /api/v1/devops/providers/:id/test_connection
        def test_connection
          credential = @provider.default_credential_for_account(current_user.account)
          unless credential
            render_error("No credentials configured for this provider", status: :unprocessable_content)
            return
          end

          result = ::Devops::Git::ProviderTestService.new(credential).test_connection

          if result[:success]
            credential.record_success!
            @provider.update_columns(metadata: @provider.metadata.merge("last_health_check_at" => Time.current.iso8601))
          else
            credential.record_failure!(result[:error])
          end

          render_success({
            provider_id: @provider.id,
            connected: result[:success],
            message: result[:success] ? result[:message] : result[:error],
            details: result.except(:success, :error, :message),
            tested_at: Time.current
          })

          log_audit_event("devops.providers.test_connection", @provider)
        rescue StandardError => e
          Rails.logger.error "Failed to test connection: #{e.message}"
          render_error("Failed to test connection: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/devops/providers/:id/sync_repositories
        def sync_repositories
          begin
            WorkerJobService.enqueue_job(
              "Devops::ProviderSyncJob",
              args: [ @provider.id ],
              queue: "devops_default"
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

          log_audit_event("devops.providers.sync_repositories", @provider)
        rescue StandardError => e
          Rails.logger.error "Failed to sync repositories: #{e.message}"
          render_error("Failed to sync repositories: #{e.message}", status: :unprocessable_content)
        end

        private

        def set_provider
          @provider = current_user.account.git_providers.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Provider not found", status: :not_found)
        end

        def require_read_permission
          return if current_user.has_permission?("devops.providers.read")

          render_error("Insufficient permissions to view DevOps providers", status: :forbidden)
        end

        def require_write_permission
          return if current_user.has_permission?("devops.providers.write")

          render_error("Insufficient permissions to manage DevOps providers", status: :forbidden)
        end

        def provider_params
          params.require(:provider).permit(
            :name,
            :provider_type,
            :api_base_url,
            :web_base_url,
            :is_active,
            capabilities: []
          )
        end

        def serialize_provider(provider, include_repositories: false)
          credential = provider.default_credential_for_account(current_user.account)
          result = {
            id: provider.id,
            name: provider.name,
            slug: provider.slug,
            provider_type: provider.provider_type,
            api_base_url: provider.effective_api_base_url,
            web_base_url: provider.effective_web_base_url,
            capabilities: provider.capabilities,
            is_active: provider.is_active,
            supports_devops: provider.supports_devops,
            supports_webhooks: provider.supports_webhooks,
            credential_status: credential ? {
              name: credential.name,
              auth_type: credential.auth_type,
              is_active: credential.is_active,
              last_test_status: credential.last_test_status,
              last_test_at: credential.last_test_at,
              external_username: credential.external_username
            } : nil,
            repository_count: provider.credentials_for_account(current_user.account)
                                      .joins(:repositories).count,
            created_at: provider.created_at,
            updated_at: provider.updated_at
          }

          if include_repositories == "true" || include_repositories == true
            repos = ::Devops::GitRepository.where(
              git_provider_credential_id: provider.credentials_for_account(current_user.account).select(:id)
            )
            result[:repositories] = repos.map do |repo|
              {
                id: repo.id,
                name: repo.name,
                full_name: repo.full_name,
                default_branch: repo.default_branch,
                is_private: repo.is_private,
                last_synced_at: repo.last_synced_at
              }
            end
          end

          result
        end
      end
    end
  end
end
