# frozen_string_literal: true

module Api
  module V1
    # Storage Providers controller
    # Manages file storage configurations and provider integrations
    class StorageProvidersController < ApplicationController
      before_action :set_storage, only: %i[show update destroy test_connection health_check set_default initialize_storage list_files]
      before_action :validate_permissions!

      # GET /api/v1/storage_providers
      def index
        storages = current_account.file_storages
                                  .includes(:account)
                                  .order(is_default: :desc, created_at: :desc)

        render_success({
          storages: storages.map(&:storage_summary),
          total_count: storages.count,
          default_storage: storages.default.first&.storage_summary
        })
      end

      # GET /api/v1/storage_providers/:id
      def show
        render_success({
          storage: @storage.storage_summary.merge(
            configuration: @storage.configuration,
            statistics: @storage.storage_provider.storage_statistics,
            capabilities: StorageProviderFactory.provider_capabilities(@storage.provider_type)
          )
        })
      end

      # POST /api/v1/storage_providers
      def create
        storage = current_account.file_storages.new(storage_create_params)

        # Encrypt sensitive configuration values
        if params[:configuration].present?
          encrypted_config = encrypt_sensitive_config(params[:configuration])
          storage.configuration = encrypted_config
        end

        if storage.save
          # Initialize storage backend if requested
          if params[:initialize] == true
            storage.storage_provider.initialize_storage
          end

          render_success(
            {
              storage: storage.storage_summary.merge(configuration: storage.configuration),
              message: "Storage configuration created successfully"
            },
            status: :created
          )
        else
          render_validation_error(storage.errors.full_messages.join(", "))
        end
      rescue StandardError => e
        Rails.logger.error "[StorageProvidersController] Create failed: #{e.message}"
        render_error("Failed to create storage configuration", status: :internal_server_error)
      end

      # PATCH/PUT /api/v1/storage_providers/:id
      def update
        update_params = storage_update_params

        # Encrypt sensitive configuration values
        if params[:configuration].present?
          encrypted_config = encrypt_sensitive_config(params[:configuration])
          update_params[:configuration] = @storage.configuration.merge(encrypted_config)
        end

        if @storage.update(update_params)
          render_success({
            storage: @storage.storage_summary.merge(configuration: @storage.configuration),
            message: "Storage configuration updated successfully"
          })
        else
          render_validation_error(@storage.errors.full_messages.join(", "))
        end
      rescue StandardError => e
        Rails.logger.error "[StorageProvidersController] Update failed: #{e.message}"
        render_error("Failed to update storage configuration", status: :internal_server_error)
      end

      # DELETE /api/v1/storage_providers/:id
      def destroy
        if @storage.is_default?
          return render_error("Cannot delete default storage configuration", status: :unprocessable_content)
        end

        if @storage.files_count > 0
          return render_error(
            "Cannot delete storage with existing files. Move files to another storage first.",
            status: :unprocessable_content
          )
        end

        if @storage.destroy
          render_success({
            deleted: true,
            message: "Storage configuration deleted successfully"
          })
        else
          render_error("Failed to delete storage configuration", status: :unprocessable_content)
        end
      end

      # POST /api/v1/storage_providers/:id/test
      def test_connection
        result = @storage.storage_provider.test_connection

        if result[:success]
          render_success({
            connected: true,
            provider_type: @storage.provider_type,
            details: result,
            message: "Storage connection successful"
          })
        else
          render_error(
            "Connection test failed: #{result[:error]}",
            status: :unprocessable_content,
            details: { details: result }
          )
        end
      rescue StandardError => e
        render_internal_error("Connection test failed", exception: e)
      end

      # GET /api/v1/storage_providers/:id/health
      def health_check
        health = @storage.storage_provider.health_check

        render_success({
          storage_id: @storage.id,
          status: health[:status],
          details: health[:details],
          checked_at: Time.current.iso8601
        })
      rescue StandardError => e
        render_internal_error("Health check failed", exception: e)
      end

      # POST /api/v1/storage_providers/:id/set_default
      def set_default
        # Unset current default
        current_account.file_storages.default.update_all(is_default: false)

        # Set new default
        if @storage.update(is_default: true)
          render_success({
            storage: @storage.storage_summary,
            message: "Default storage updated successfully"
          })
        else
          render_error("Failed to set default storage", status: :unprocessable_content)
        end
      end

      # GET /api/v1/storage_providers/supported
      def supported
        providers = StorageProviderFactory.supported_providers.map do |provider_type|
          capabilities = StorageProviderFactory.provider_capabilities(provider_type)
          dependencies = StorageProviderFactory.check_dependencies(provider_type)

          {
            provider_type: provider_type,
            available: dependencies[:available],
            missing_dependencies: dependencies[:missing],
            capabilities: capabilities
          }
        end

        render_success({
          providers: providers,
          total_count: providers.count
        })
      end

      # POST /api/v1/storage_providers/:id/initialize
      def initialize_storage
        result = @storage.storage_provider.initialize_storage

        if result
          render_success({
            initialized: true,
            storage: @storage.storage_summary,
            message: "Storage backend initialized successfully"
          })
        else
          render_error("Failed to initialize storage backend", status: :unprocessable_content)
        end
      rescue StandardError => e
        render_internal_error("Initialization failed", exception: e)
      end

      # GET /api/v1/storage_providers/:id/files
      def list_files
        prefix = params[:prefix]
        options = {
          max_keys: params[:max_keys]&.to_i || 100
        }

        files = @storage.storage_provider.list_files(prefix: prefix, options: options)

        render_success({
          storage_id: @storage.id,
          prefix: prefix,
          files: files,
          count: files.count
        })
      rescue StandardError => e
        render_internal_error("Failed to list files", exception: e)
      end

      # GET /api/v1/storage_providers/stats
      def aggregate_stats
        storages = current_account.file_storages

        total_files = 0
        total_size = 0
        total_quota = 0
        provider_breakdown = Hash.new { |h, k| h[k] = { files: 0, size: 0 } }

        storages.each do |storage|
          total_files += storage.files_count
          total_size += storage.total_size_bytes
          total_quota += storage.quota_bytes if storage.quota_enabled?

          provider_breakdown[storage.provider_type][:files] += storage.files_count
          provider_breakdown[storage.provider_type][:size] += storage.total_size_bytes
        end

        render_success({
          total_files: total_files,
          total_size_bytes: total_size,
          total_quota_bytes: total_quota,
          quota_enabled: total_quota > 0,
          usage_percentage: total_quota > 0 ? ((total_size.to_f / total_quota) * 100).round(2) : 0,
          providers: provider_breakdown.map do |type, stats|
            {
              provider_type: type,
              files_count: stats[:files],
              total_size_bytes: stats[:size]
            }
          end,
          storages_count: storages.count
        })
      end

      private

      def set_storage
        @storage = current_account.file_storages.find_by(id: params[:id])

        unless @storage
          render_error("Storage configuration not found", status: :not_found)
        end
      end

      def validate_permissions!
        case action_name
        when "index", "show", "supported", "aggregate_stats", "health_check", "list_files"
          require_any_permission("admin.storage.read", "admin.storage.manage")
        when "create"
          require_any_permission("admin.storage.create", "admin.storage.manage")
        when "update", "set_default", "initialize_storage", "test_connection"
          require_any_permission("admin.storage.update", "admin.storage.manage")
        when "destroy"
          require_any_permission("admin.storage.delete", "admin.storage.manage")
        end
      end

      def storage_create_params
        params.permit(
          :name,
          :provider_type,
          :is_default,
          :quota_enabled,
          :quota_bytes,
          blocked_extensions: [],
          blocked_mime_types: []
        )
      end

      def storage_update_params
        params.permit(
          :name,
          :quota_enabled,
          :quota_bytes,
          blocked_extensions: [],
          blocked_mime_types: []
        )
      end

      def encrypt_sensitive_config(config)
        sensitive_keys = %w[
          access_key_id
          secret_access_key
          password
          api_key
          credentials
        ]

        encrypted = config.dup

        sensitive_keys.each do |key|
          next unless encrypted[key].present?

          # Skip if already encrypted
          next if encrypted[key].to_s.start_with?("encrypted:")

          # Encrypt sensitive value
          encryptor = ::Ai::CredentialEncryptionService.new
          encrypted_value = encryptor.encrypt(encrypted[key])
          encrypted[key] = "encrypted:#{encrypted_value}"
        end

        encrypted
      end
    end
  end
end
