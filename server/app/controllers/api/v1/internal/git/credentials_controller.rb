# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Git
        class CredentialsController < InternalBaseController
          include Api::V1::Internal::WorkerTenancy

          before_action :set_credential, except: [ :index ]

          # GET /api/v1/internal/git/credentials
          def index
            # Constrained to the calling worker's account (credential_scope);
            # a caller-supplied account_id can only NARROW within it, never
            # widen to another tenant.
            credentials = credential_scope.includes(:provider)
            credentials = credentials.where(account_id: params[:account_id]) if params[:account_id].present?
            credentials = credentials.active if params[:active] == "true"

            render_success(credentials.limit(500).map { |c| serialize_credential(c) })
          end

          # GET /api/v1/internal/git/credentials/:id
          def show
            render_success(serialize_credential(@credential))
          end

          # GET /api/v1/internal/git/credentials/:id/repositories
          def repositories
            repos = @credential.repositories

            render_success(repos.map { |repo| serialize_repository(repo) })
          end

          # GET /api/v1/internal/git/credentials/:id/decrypted
          def decrypted
            # Worker can access decrypted credentials for API operations
            credentials = @credential.credentials

            render_success({
              id: @credential.id,
              auth_type: @credential.auth_type,
              credentials: credentials,
              provider: {
                id: @credential.git_provider.id,
                provider_type: @credential.git_provider.provider_type,
                api_base_url: @credential.git_provider.api_base_url,
                web_base_url: @credential.git_provider.web_base_url
              }
            })
          rescue StandardError => e
            # Log credential ID and error class only - no sensitive decryption details
            Rails.logger.error "Failed to decrypt Git credential #{@credential.id}: #{e.class.name}"
            render_error("Failed to decrypt credentials", status: :internal_server_error)
          end

          private

          def set_credential
            # Anchored to the calling worker's account. #decrypted renders the
            # PLAINTEXT git token, so a bare `find(params[:id])` disclosed any
            # account's tokens by enumerable id. Cross-account id -> 404 (not
            # 403): existence must not leak. See Api::V1::Internal::WorkerTenancy.
            @credential = credential_scope.includes(:provider).find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error("Credential not found", status: :not_found)
          end

          # Tenancy scope: git credentials owned by the authenticated worker's
          # account. `git_provider_credentials.account_id` is NOT NULL, so a nil
          # worker account_id (fail-closed) catches no rows.
          def credential_scope
            ::Devops::GitProviderCredential.where(account_id: worker_account_id)
          end

          def serialize_credential(credential)
            {
              id: credential.id,
              name: credential.name,
              auth_type: credential.auth_type,
              external_username: credential.external_username,
              external_user_id: credential.external_user_id,
              is_active: credential.is_active,
              is_default: credential.is_default,
              scopes: credential.scopes,
              last_used_at: credential.last_used_at&.iso8601,
              last_test_status: credential.last_test_status,
              expires_at: credential.expires_at&.iso8601,
              success_count: credential.success_count,
              failure_count: credential.failure_count,
              consecutive_failures: credential.consecutive_failures,
              healthy: credential.healthy?,
              can_be_used: credential.can_be_used?,
              account_id: credential.account_id,
              provider_type: credential.git_provider.provider_type,
              api_base_url: credential.git_provider.api_base_url,
              status: credential.is_active ? "active" : "inactive",
              provider: {
                id: credential.git_provider.id,
                name: credential.git_provider.name,
                provider_type: credential.git_provider.provider_type,
                api_base_url: credential.git_provider.api_base_url,
                web_base_url: credential.git_provider.web_base_url,
                supports_devops: credential.git_provider.supports_devops
              }
            }
          end

          def serialize_repository(repo)
            {
              id: repo.id,
              name: repo.name,
              full_name: repo.full_name,
              owner: repo.owner,
              default_branch: repo.default_branch,
              provider_type: repo.git_provider&.provider_type
            }
          end
        end
      end
    end
  end
end
