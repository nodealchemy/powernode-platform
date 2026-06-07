# frozen_string_literal: true

module Security
  class VaultCredentialProvider
    class CredentialError < StandardError; end

    CREDENTIAL_TYPES = {
      ai_provider: "ai-providers",
      mcp_server: "mcp-servers",
      chat_channel: "chat-channels",
      git_credential: "git-credentials",
      wireguard_node_key: "wireguard-node-keys",
      wireguard_user_key: "wireguard-user-keys",
      federation_trust_jwt: "sdwan-federation-trust-jwts",
      # Per-node Ed25519 signing keypair. Used to sign membership
      # credentials, control-plane messages, and multipath probes. Stored
      # alongside the existing X25519 wireguard_node_key — same VaultCredential
      # plumbing, distinct vault path so rotations are independent.
      node_signing_key: "sdwan-node-signing-keys",
      # Per-constellation Ed25519 signing keypair. The constellation is
      # the platform's signed-manifest scope; its signing key is what the
      # MC signer uses to seal each MembershipCredential envelope. The
      # public half is published in the constellation manifest; the
      # private half lives only in Vault.
      constellation_signing_key: "sdwan-constellation-signing-keys",
      # Docker daemon mTLS material — platform-side client cert/key for
      # calling a managed `dockerd` over the SDWAN overlay. The CA chain
      # comes from `System::InternalCaService.ca_chain_pem`; only the
      # client half ({cert_pem, key_pem, serial, not_after}) is stored
      # here, keyed by `Devops::DockerHost.id`.
      docker_daemon_tls: "docker-daemon-tls",
      # ACME-issued TLS certificate material. Stores {cert_pem,
      # private_key_pem, chain_pem, account_key_pem} per
      # System::AcmeCertificate.id. Used by Traefik for TLS termination
      # on the platform's public listeners.
      # Plan reference: Decentralized Federation §J + P2.5.
      acme_certificate: "acme-certificates",
      # DNS provider API credentials used to solve the ACME DNS-01
      # challenge during cert issuance/renewal. Stores provider-specific
      # token structures per System::AcmeDnsCredential.id (e.g.
      # Cloudflare API token, Route53 access key + secret, etc.).
      acme_dns: "acme-dns-credentials",
      # PostgreSQL streaming-replication credentials issued to a
      # cluster_member spawn child. Stores {username, password, slot_name,
      # primary_host, primary_port} keyed by System::FederationPeer.id.
      # The child reads these (one-time during accept) to configure its
      # pg-replica module's recovery.conf.
      # Plan reference: Decentralized Federation §H + P6.4.
      cluster_member_pg_replica: "cluster-member-pg-replica",
      # External data-source API credential material (API keys, bearer tokens,
      # HMAC shared secrets, AWS access/secret keys). Stored per
      # Ai::DataSourceCredential.id and read by Ai::DataSources::QueryService when
      # the credential carries a vault_path; the on-the-wire signer
      # (Ai::DataSources::Auth::SignerRegistry) consumes the returned material.
      data_source: "data-sources",
      custom: "custom"
    }.freeze

    def initialize(account_id:)
      @account_id = account_id
      @vault_available = vault_available?
    end

    # Get credential with Vault fallback to database
    def get_credential(credential_type:, credential_id:, record: nil)
      type_path = CREDENTIAL_TYPES[credential_type.to_sym] || credential_type.to_s

      # Try Vault first if available
      if @vault_available && record&.vault_path.present?
        begin
          return VaultClient.read_secret(record.vault_path)
        rescue VaultClient::SecretNotFoundError, VaultClient::ConnectionError => e
          Rails.logger.warn "Vault read failed, falling back to database: #{e.message}"
        end
      end

      # Try Vault by convention path
      if @vault_available
        begin
          credential = VaultClient.get_credential(
            account_id: @account_id,
            credential_type: type_path,
            credential_id: credential_id
          )
          return credential if credential.present?
        rescue VaultClient::VaultError => e
          Rails.logger.warn "Vault credential lookup failed: #{e.message}"
        end
      end

      # Fallback to database encryption
      return nil unless record
      return nil unless record.respond_to?(:credentials)

      record.credentials
    end

    # Store credential in Vault (with database fallback)
    def store_credential(credential_type:, credential_id:, data:, record: nil)
      type_path = CREDENTIAL_TYPES[credential_type.to_sym] || credential_type.to_s

      if @vault_available
        begin
          vault_path = VaultClient.store_credential(
            account_id: @account_id,
            credential_type: type_path,
            credential_id: credential_id,
            data: data
          )

          # Update record with vault path
          if record.respond_to?(:vault_path=)
            record.update!(
              vault_path: vault_path,
              migrated_to_vault_at: Time.current
            )
          end

          return { stored_in: :vault, path: vault_path }
        rescue VaultClient::VaultError => e
          Rails.logger.error "Failed to store credential in Vault: #{e.message}"
          # Fall through to database storage
        end
      end

      # Fallback to database encryption
      if record.respond_to?(:credentials=)
        record.credentials = data
        record.save!
        return { stored_in: :database }
      end

      raise CredentialError, "No storage method available for credential"
    end

    # Delete credential from Vault and/or database
    def delete_credential(credential_type:, credential_id:, record: nil)
      type_path = CREDENTIAL_TYPES[credential_type.to_sym] || credential_type.to_s

      # Delete from Vault if path exists
      if @vault_available && record&.vault_path.present?
        begin
          VaultClient.delete_secret(record.vault_path)
        rescue VaultClient::VaultError => e
          Rails.logger.warn "Failed to delete from Vault: #{e.message}"
        end
      end

      # Clear database credential
      if record.respond_to?(:encrypted_credentials=)
        record.update!(
          encrypted_credentials: nil,
          vault_path: nil,
          migrated_to_vault_at: nil
        )
      end

      true
    end

    # Rotate credential
    def rotate_credential(credential_type:, credential_id:, new_data:, record: nil)
      type_path = CREDENTIAL_TYPES[credential_type.to_sym] || credential_type.to_s

      if @vault_available
        begin
          VaultClient.rotate_credential(
            account_id: @account_id,
            credential_type: type_path,
            credential_id: credential_id,
            new_data: new_data
          )

          # Clear database copy if it exists
          if record&.respond_to?(:encrypted_credentials=) && record.encrypted_credentials.present?
            record.update!(encrypted_credentials: nil)
          end

          return { rotated_in: :vault }
        rescue VaultClient::VaultError => e
          Rails.logger.error "Failed to rotate credential in Vault: #{e.message}"
        end
      end

      # Fallback: store in database
      if record.respond_to?(:credentials=)
        record.credentials = new_data
        record.save!
        return { rotated_in: :database }
      end

      raise CredentialError, "No storage method available for rotation"
    end

    # Check if credential is stored in Vault
    def stored_in_vault?(record)
      record&.vault_path.present? && record.migrated_to_vault_at.present?
    end

    # Get credential storage status
    def credential_status(record)
      {
        vault_path: record&.vault_path,
        migrated_to_vault_at: record&.migrated_to_vault_at,
        has_database_encryption: record&.encrypted_credentials.present?,
        vault_available: @vault_available,
        storage_location: determine_storage_location(record)
      }
    end

    private

    def vault_available?
      return false if Rails.env.test?

      VaultClient.healthy?
    rescue StandardError => e
      Rails.logger.warn "Vault availability check failed: #{e.message}"
      false
    end

    def determine_storage_location(record)
      return :none unless record

      if record.vault_path.present? && record.migrated_to_vault_at.present?
        :vault
      elsif record.respond_to?(:encrypted_credentials) && record.encrypted_credentials.present?
        :database
      else
        :none
      end
    end
  end
end
