# frozen_string_literal: true

module Security
  class VaultMigrationService
    class MigrationError < StandardError; end

    attr_reader :migrated_count, :failed_count, :skipped_count

    def initialize(dry_run: false)
      @vault = VaultClient.new
      @dry_run = dry_run
      @migrated_count = 0
      @failed_count = 0
      @skipped_count = 0
      @errors = []
    end

    # Migrate all AI provider credentials
    def migrate_ai_provider_credentials
      Rails.logger.info "Starting AI provider credential migration to Vault (dry_run: #{@dry_run})"

      Ai::ProviderCredential.where(vault_path: nil).find_each do |credential|
        migrate_ai_credential(credential)
      end

      log_migration_summary("AI Provider Credentials")
    end

    # Migrate all DevOps integration credentials
    def migrate_devops_integration_credentials
      Rails.logger.info "Starting DevOps integration credential migration to Vault (dry_run: #{@dry_run})"

      Devops::IntegrationCredential.where(vault_path: nil).find_each do |credential|
        migrate_devops_credential(credential)
      end

      log_migration_summary("DevOps Integration Credentials")
    end

    # Migrate MCP server OAuth tokens
    def migrate_mcp_server_credentials
      Rails.logger.info "Starting MCP server credential migration to Vault (dry_run: #{@dry_run})"

      McpServer.where(vault_path: nil).where.not(encrypted_oauth_access_token: nil).find_each do |server|
        migrate_mcp_credential(server)
      end

      log_migration_summary("MCP Server Credentials")
    end

    # Migrate all credentials
    def migrate_all
      reset_counters

      migrate_ai_provider_credentials
      migrate_devops_integration_credentials
      migrate_mcp_server_credentials

      {
        total_migrated: @migrated_count,
        total_failed: @failed_count,
        total_skipped: @skipped_count,
        errors: @errors.take(50)  # Limit error output
      }
    end

    # Verify migration integrity
    def verify_migrations
      results = {
        ai_provider_credentials: verify_ai_credentials,
        devops_credentials: verify_devops_credentials,
        mcp_credentials: verify_mcp_credentials
      }

      results[:all_valid] = results.values.all? { |r| r[:invalid_count].zero? }
      results
    end

    # Rollback migration for a specific credential
    def rollback_credential(record)
      return unless record.vault_path.present?

      # Re-encrypt to database
      begin
        decrypted = @vault.read_secret(record.vault_path)

        case record
        when Ai::ProviderCredential
          record.credentials = decrypted
        when Devops::IntegrationCredential
          record.credentials = decrypted
        when McpServer
          record.oauth_access_token = decrypted[:access_token]
          record.oauth_refresh_token = decrypted[:refresh_token] if decrypted[:refresh_token]
        end

        record.vault_path = nil
        record.migrated_to_vault_at = nil
        record.save!

        Rails.logger.info "Rolled back credential #{record.id} to database encryption"
        true
      rescue StandardError => e
        Rails.logger.error "Failed to rollback credential #{record.id}: #{e.message}"
        false
      end
    end

    private

    def migrate_ai_credential(credential)
      return skip_reason(credential, "No encrypted credentials") unless credential.encrypted_credentials.present?

      begin
        # Decrypt from database
        decrypted = credential.credentials

        return skip_reason(credential, "Empty credentials") if decrypted.blank?

        if @dry_run
          Rails.logger.info "[DRY RUN] Would migrate AI credential #{credential.id}"
          @migrated_count += 1
          return
        end

        # Store in Vault
        vault_path = @vault.store_credential(
          account_id: credential.account_id,
          credential_type: "ai-providers",
          credential_id: credential.id,
          data: decrypted.merge(
            provider_id: credential.ai_provider_id,
            provider_name: credential.provider&.name,
            credential_name: credential.name
          )
        )

        # Update record with Vault path, clear encrypted data
        credential.update!(
          vault_path: vault_path,
          migrated_to_vault_at: Time.current
          # Note: We keep encrypted_credentials as backup initially
          # Clear with: encrypted_credentials: nil
        )

        @migrated_count += 1
        Rails.logger.info "Migrated AI credential #{credential.id} to Vault"
      rescue StandardError => e
        @failed_count += 1
        @errors << { type: "ai_provider", id: credential.id, error: e.message }
        Rails.logger.error "Failed to migrate AI credential #{credential.id}: #{e.message}"
      end
    end

    def migrate_devops_credential(credential)
      return skip_reason(credential, "No encrypted credentials") unless credential.encrypted_credentials.present?

      begin
        decrypted = credential.credentials

        return skip_reason(credential, "Empty credentials") if decrypted.blank?

        if @dry_run
          Rails.logger.info "[DRY RUN] Would migrate DevOps credential #{credential.id}"
          @migrated_count += 1
          return
        end

        vault_path = @vault.store_credential(
          account_id: credential.account_id,
          credential_type: "git-credentials",
          credential_id: credential.id,
          data: decrypted.merge(
            credential_type: credential.credential_type,
            credential_name: credential.name
          )
        )

        credential.update!(
          vault_path: vault_path,
          migrated_to_vault_at: Time.current
        )

        @migrated_count += 1
        Rails.logger.info "Migrated DevOps credential #{credential.id} to Vault"
      rescue StandardError => e
        @failed_count += 1
        @errors << { type: "devops", id: credential.id, error: e.message }
        Rails.logger.error "Failed to migrate DevOps credential #{credential.id}: #{e.message}"
      end
    end

    def migrate_mcp_credential(server)
      begin
        oauth_data = {}
        oauth_data[:access_token] = server.oauth_access_token if server.encrypted_oauth_access_token.present?
        oauth_data[:refresh_token] = server.oauth_refresh_token if server.encrypted_oauth_refresh_token.present?
        oauth_data[:token_expires_at] = server.oauth_token_expires_at if server.oauth_token_expires_at.present?

        return skip_reason(server, "No OAuth data") if oauth_data.empty?

        if @dry_run
          Rails.logger.info "[DRY RUN] Would migrate MCP server #{server.id}"
          @migrated_count += 1
          return
        end

        vault_path = @vault.store_credential(
          account_id: server.account_id,
          credential_type: "mcp-servers",
          credential_id: server.id,
          data: oauth_data.merge(
            server_name: server.name,
            server_url: server.url
          )
        )

        server.update!(
          vault_path: vault_path,
          migrated_to_vault_at: Time.current
        )

        @migrated_count += 1
        Rails.logger.info "Migrated MCP server #{server.id} to Vault"
      rescue StandardError => e
        @failed_count += 1
        @errors << { type: "mcp_server", id: server.id, error: e.message }
        Rails.logger.error "Failed to migrate MCP server #{server.id}: #{e.message}"
      end
    end

    def verify_ai_credentials
      valid_count = 0
      invalid_count = 0

      Ai::ProviderCredential.where.not(vault_path: nil).find_each do |credential|
        begin
          vault_data = @vault.read_secret(credential.vault_path)
          if vault_data.present? && vault_data[:api_key].present?
            valid_count += 1
          else
            invalid_count += 1
          end
        rescue StandardError
          invalid_count += 1
        end
      end

      { valid_count: valid_count, invalid_count: invalid_count }
    end

    def verify_devops_credentials
      valid_count = 0
      invalid_count = 0

      Devops::IntegrationCredential.where.not(vault_path: nil).find_each do |credential|
        begin
          vault_data = @vault.read_secret(credential.vault_path)
          valid_count += 1 if vault_data.present?
        rescue StandardError
          invalid_count += 1
        end
      end

      { valid_count: valid_count, invalid_count: invalid_count }
    end

    def verify_mcp_credentials
      valid_count = 0
      invalid_count = 0

      McpServer.where.not(vault_path: nil).find_each do |server|
        begin
          vault_data = @vault.read_secret(server.vault_path)
          valid_count += 1 if vault_data.present?
        rescue StandardError
          invalid_count += 1
        end
      end

      { valid_count: valid_count, invalid_count: invalid_count }
    end

    def skip_reason(record, reason)
      @skipped_count += 1
      Rails.logger.debug "Skipped #{record.class}##{record.id}: #{reason}"
    end

    def reset_counters
      @migrated_count = 0
      @failed_count = 0
      @skipped_count = 0
      @errors = []
    end

    def log_migration_summary(type)
      Rails.logger.info <<~SUMMARY
        #{type} Migration Summary:
          Migrated: #{@migrated_count}
          Failed: #{@failed_count}
          Skipped: #{@skipped_count}
          Dry Run: #{@dry_run}
      SUMMARY
    end
  end
end
