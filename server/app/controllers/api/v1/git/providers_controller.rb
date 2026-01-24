# frozen_string_literal: true

module Api
  module V1
    module Git
      class ProvidersController < ApplicationController
        before_action :set_provider, only: %i[
          show update destroy
          credentials create_credential destroy_credential test_credential make_default
          available_repositories import_repositories
          oauth_authorize oauth_callback
        ]
        before_action :set_credential, only: %i[destroy_credential test_credential make_default available_repositories import_repositories]
        before_action :validate_permissions

        # GET /api/v1/git/providers
        def index
          providers = ::Devops::GitProvider.active.ordered_by_priority

          # Filter by provider_type
          providers = providers.where(provider_type: params[:provider_type]) if params[:provider_type].present?

          # Search by name
          providers = providers.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?

          # Pagination
          page = (params[:page] || 1).to_i
          per_page = (params[:per_page] || 20).to_i
          total_count = providers.count
          providers = providers.offset((page - 1) * per_page).limit(per_page)

          render_success({
            providers: providers.map { |p| serialize_provider(p) },
            count: total_count,
            pagination: {
              current_page: page,
              per_page: per_page,
              total_count: total_count,
              total_pages: (total_count.to_f / per_page).ceil
            }
          })
        end

        # GET /api/v1/git/providers/:id
        def show
          render_success({ provider: serialize_provider_detail(@provider) })
        end

        # POST /api/v1/git/providers
        def create
          @provider = ::Devops::GitProvider.new(provider_params)

          if @provider.save
            render_success({ provider: serialize_provider_detail(@provider) }, status: :created)
          else
            render_validation_error(@provider.errors)
          end
        end

        # PATCH /api/v1/git/providers/:id
        def update
          if @provider.update(provider_params)
            render_success({ provider: serialize_provider_detail(@provider) })
          else
            render_validation_error(@provider.errors)
          end
        end

        # DELETE /api/v1/git/providers/:id
        def destroy
          if @provider.destroy
            render_success(message: "Git provider deleted successfully")
          else
            render_validation_error(@provider.errors)
          end
        end

        # GET /api/v1/git/providers/available
        def available
          providers = ::Devops::GitProvider.active.ordered_by_priority.map do |provider|
            {
              id: provider.id,
              name: provider.name,
              slug: provider.slug,
              provider_type: provider.provider_type,
              description: provider.description,
              api_base_url: provider.api_base_url,
              web_base_url: provider.web_base_url,
              supports_oauth: provider.supports_oauth,
              supports_pat: provider.supports_pat,
              supports_devops: provider.supports_devops,
              capabilities: provider.capabilities,
              configured: current_user.account.git_provider_credentials
                            .where(provider: provider, is_active: true).exists?
            }
          end

          render_success({ providers: providers })
        end

        # ============================================
        # CREDENTIALS - Nested Resource
        # ============================================

        # GET /api/v1/git/providers/:id/credentials
        def credentials
          creds = current_user.account.git_provider_credentials
                    .where(provider: @provider)
                    .includes(:provider)
                    .order(is_default: :desc, created_at: :desc)

          render_success({
            credentials: creds.map { |c| serialize_credential(c) },
            count: creds.count
          })
        end

        # POST /api/v1/git/providers/:id/credentials
        def create_credential
          @credential = ::Devops::Git::ProviderManagementService.create_credential(
            @provider,
            current_user.account,
            current_user,
            credential_params
          )

          if @credential.persisted?
            render_success({ credential: serialize_credential_detail(@credential) }, status: :created)
          else
            render_validation_error(@credential.errors)
          end
        rescue ::Devops::Git::ProviderManagementService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # DELETE /api/v1/git/providers/:id/credentials/:credential_id
        def destroy_credential
          if @credential.destroy
            render_success(message: "Credential deleted successfully")
          else
            render_validation_error(@credential.errors)
          end
        end

        # POST /api/v1/git/providers/:id/credentials/:credential_id/test
        def test_credential
          result = ::Devops::Git::ProviderTestService.new(@credential).test_with_rate_limit

          if result[:success]
            @credential.record_success!
          else
            @credential.record_failure!(result[:error])
          end

          render_success(result)
        end

        # POST /api/v1/git/providers/:id/credentials/:credential_id/make_default
        def make_default
          @credential.make_default!
          render_success({
            credential: serialize_credential(@credential),
            message: "Credential set as default"
          })
        end

        # GET /api/v1/git/providers/:id/credentials/:credential_id/available_repositories
        # Lists repositories from the provider without importing them
        def available_repositories
          result = ::Devops::Git::ProviderManagementService.list_available_repositories(
            @credential,
            page: params[:page]&.to_i || 1,
            per_page: params[:per_page]&.to_i || 100,
            include_archived: params[:include_archived] == "true",
            include_forks: params[:include_forks] == "true",
            search: params[:search]
          )

          if result[:success]
            # Get current usage and limit
            current_count = current_user.account.git_repositories.count
            max_limit = repository_limit

            render_success({
              repositories: result[:repositories],
              pagination: result[:pagination],
              usage: {
                current: current_count,
                limit: max_limit,
                available: [ max_limit - current_count, 0 ].max
              }
            })
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        rescue ::Devops::Git::ProviderManagementService::CredentialError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/git/providers/:id/credentials/:credential_id/import_repositories
        # Imports specific repositories by external_id
        def import_repositories
          external_ids = params[:external_ids] || []

          if external_ids.empty?
            return render_error("No repositories selected for import", status: :unprocessable_content)
          end

          # Check plan limits
          current_count = current_user.account.git_repositories.count
          max_limit = repository_limit
          available_slots = max_limit - current_count

          if external_ids.count > available_slots
            return render_error(
              "Cannot import #{external_ids.count} repositories. Your plan allows #{max_limit} repositories and you have #{current_count} imported. #{available_slots} slots available.",
              status: :unprocessable_content
            )
          end

          result = ::Devops::Git::ProviderManagementService.import_specific_repositories(
            @credential,
            external_ids,
            include_archived: params[:include_archived] == "true",
            include_forks: params[:include_forks] == "true"
          )

          if result[:success]
            render_success({
              imported_count: result[:imported_count],
              error_count: result[:error_count],
              repositories: result[:repositories]&.map { |r| serialize_repository(r) },
              errors: result[:errors],
              usage: {
                current: current_user.account.git_repositories.count,
                limit: max_limit
              },
              message: "Imported #{result[:imported_count]} repositories"
            })
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        rescue ::Devops::Git::ProviderManagementService::CredentialError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/git/providers/:id/credentials/:credential_id/sync_repositories
        # @deprecated Use import_repositories instead
        def sync_repositories
          result = ::Devops::Git::ProviderManagementService.sync_repositories(
            @credential,
            page: params[:page]&.to_i || 1,
            per_page: params[:per_page]&.to_i || 100,
            include_archived: params[:include_archived] == "true",
            include_forks: params[:include_forks] == "true"
          )

          if result[:success]
            render_success({
              synced_count: result[:synced_count],
              error_count: result[:error_count],
              repositories: result[:repositories]&.map { |r| serialize_repository(r) },
              errors: result[:errors],
              message: "Synced #{result[:synced_count]} repositories"
            })
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        rescue ::Devops::Git::ProviderManagementService::CredentialError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # ============================================
        # OAUTH FLOW
        # ============================================

        # POST /api/v1/git/providers/:id/oauth/authorize
        def oauth_authorize
          unless @provider.supports_oauth
            return render_error("Provider does not support OAuth", status: :unprocessable_content)
          end

          oauth_service = ::Devops::Git::OAuthService.new(@provider, current_user.account)
          auth_url = oauth_service.authorization_url(
            redirect_uri: params[:redirect_uri],
            state: oauth_service.generate_state(current_user)
          )

          render_success({ authorization_url: auth_url })
        end

        # POST /api/v1/git/providers/:id/oauth/callback
        def oauth_callback
          oauth_service = ::Devops::Git::OAuthService.new(@provider, current_user.account)

          result = oauth_service.handle_callback(
            code: params[:code],
            state: params[:state]
          )

          if result[:success]
            @credential = result[:credential]
            render_success({
              credential: serialize_credential_detail(@credential),
              message: "OAuth connection successful"
            })
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        rescue ::Devops::Git::OAuthService::OAuthError => e
          render_error(e.message, status: :unprocessable_content)
        end

        private

        def set_provider
          @provider = ::Devops::GitProvider.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Provider not found", status: :not_found)
        end

        def set_credential
          @credential = current_user.account.git_provider_credentials
                          .where(provider: @provider)
                          .find(params[:credential_id])
        rescue ActiveRecord::RecordNotFound
          render_error("Credential not found", status: :not_found)
        end

        def validate_permissions
          case action_name
          when "index", "show", "available"
            require_permission("git.providers.read")
          when "create"
            require_permission("git.providers.create")
          when "update"
            require_permission("git.providers.update")
          when "destroy"
            require_permission("git.providers.delete")
          when "credentials"
            require_permission("git.credentials.read")
          when "create_credential"
            require_permission("git.credentials.create")
          when "destroy_credential"
            require_permission("git.credentials.delete")
          when "test_credential"
            require_permission("git.credentials.test")
          when "make_default"
            require_permission("git.credentials.update")
          when "oauth_authorize", "oauth_callback"
            require_permission("git.credentials.create")
          when "available_repositories"
            require_permission("git.repositories.read")
          when "import_repositories", "sync_repositories"
            require_permission("git.repositories.sync")
          end
        end

        def repository_limit
          subscription = current_user.account.subscription
          return 10 unless subscription&.plan # Default fallback

          subscription.plan.get_limit("max_repositories") || 10
        end

        def provider_params
          params.require(:provider).permit(
            :name, :slug, :provider_type, :description,
            :api_base_url, :web_base_url, :is_active,
            :supports_oauth, :supports_pat, :supports_webhooks, :supports_devops,
            :priority_order,
            capabilities: [],
            oauth_config: {},
            webhook_config: {},
            devops_config: {},
            metadata: {}
          )
        end

        def credential_params
          params.require(:credential).permit(
            :name, :auth_type, :is_active, :is_default, :expires_at,
            credentials: {}
          )
        end

        def serialize_provider(provider)
          {
            id: provider.id,
            name: provider.name,
            slug: provider.slug,
            provider_type: provider.provider_type,
            is_active: provider.is_active,
            supports_oauth: provider.supports_oauth,
            supports_pat: provider.supports_pat,
            supports_webhooks: provider.supports_webhooks,
            supports_devops: provider.supports_devops,
            capabilities: provider.capabilities,
            priority_order: provider.priority_order,
            created_at: provider.created_at.iso8601
          }
        end

        def serialize_provider_detail(provider)
          serialize_provider(provider).merge(
            description: provider.description,
            api_base_url: provider.api_base_url,
            web_base_url: provider.web_base_url,
            oauth_config: provider.oauth_config.except("client_secret"),
            webhook_config: provider.webhook_config,
            devops_config: provider.devops_config,
            metadata: provider.metadata,
            credentials_count: provider.credentials
                                .where(account: current_user.account).count
          )
        end

        def serialize_credential(credential)
          {
            id: credential.id,
            name: credential.name,
            auth_type: credential.auth_type,
            provider_type: credential.provider_type,
            external_username: credential.external_username,
            external_avatar_url: credential.external_avatar_url,
            is_active: credential.is_active,
            is_default: credential.is_default,
            scopes: credential.scopes,
            last_used_at: credential.last_used_at&.iso8601,
            last_test_status: credential.last_test_status,
            expires_at: credential.expires_at&.iso8601,
            created_at: credential.created_at.iso8601,
            stats: {
              success_count: credential.success_count,
              failure_count: credential.failure_count,
              consecutive_failures: credential.consecutive_failures,
              repositories_count: credential.repositories.count
            }
          }
        end

        def serialize_credential_detail(credential)
          serialize_credential(credential).merge(
            last_error: credential.last_error,
            last_test_at: credential.last_test_at&.iso8601,
            healthy: credential.healthy?,
            can_be_used: credential.can_be_used?,
            git_provider: serialize_provider(credential.git_provider)
          )
        end

        def serialize_repository(repository)
          {
            id: repository.id,
            name: repository.name,
            full_name: repository.full_name,
            owner: repository.owner,
            description: repository.description,
            default_branch: repository.default_branch,
            web_url: repository.web_url,
            is_private: repository.is_private,
            is_fork: repository.is_fork,
            is_archived: repository.is_archived,
            stars_count: repository.stars_count,
            forks_count: repository.forks_count,
            languages: repository.languages,
            topics: repository.topics,
            last_synced_at: repository.last_synced_at&.iso8601,
            created_at: repository.created_at.iso8601
          }
        end
      end
    end
  end
end
