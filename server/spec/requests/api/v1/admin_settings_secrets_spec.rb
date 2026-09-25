# frozen_string_literal: true

require 'rails_helper'

# fc-38 decision #3: redis_config's "password" and vault_config's
# "vault_role_id"/"vault_secret_id" used to be stored PLAINTEXT inside their
# AdminSetting JSON blobs. These specs assert the stored value is CIPHERTEXT
# and that both GET responses mask it — never asserting an exact plaintext
# value that could appear in a failure message (only presence/absence and a
# decrypt-round-trips-correctly check via Security::CredentialEncryptionService
# directly, which is how the app itself will read it back).
RSpec.describe 'Api::V1::AdminSettings secrets hardening', type: :request do
  let(:account) { create(:account) }
  let(:security_headers) { auth_headers_for(create(:user, account: account, permissions: %w[admin.settings.read admin.settings.security])) }
  let(:read_headers) { auth_headers_for(create(:user, account: account, permissions: %w[admin.settings.read])) }

  # Pre-existing, unrelated defect found while writing these specs (not fixed
  # here — see the fc-38 report): log_audit_event(action, "SystemSettings",
  # ...) passes a bare String as `resource`, and AuditLog.log_action
  # unconditionally calls `resource.id` / `resource.class.name` on it — String
  # has neither. In production this is swallowed silently (log_audit_event's
  # own rescue only re-raises `if Rails.env.test?`), so the setting save still
  # succeeds but its audit log entry is silently never created; in test it
  # surfaces as a 422 on every PUT unless Audit::LoggingService is stubbed —
  # stubbed here (matching the existing convention in admin_settings_spec.rb)
  # so it does not mask the encryption behaviour these specs exist to check.
  before do
    allow(Audit::LoggingService.instance).to receive(:log).and_return(nil)
  end

  describe 'PUT /api/v1/admin_settings/infrastructure (redis password)' do
    let(:redis_password) { "redis-test-secret-#{SecureRandom.hex(4)}" }

    it 'never stores the password in the redis_config blob' do
      put '/api/v1/admin_settings/infrastructure',
          params: { redis: { host: '127.0.0.1', port: 6379, password: redis_password } },
          headers: security_headers, as: :json

      expect_success_response

      blob = AdminSetting.find_by(key: 'redis_config')
      expect(blob).not_to be_nil
      expect(blob.value).not_to include(redis_password)
    end

    it 'stores the password encrypted, decryptable via Security::CredentialEncryptionService' do
      put '/api/v1/admin_settings/infrastructure',
          params: { redis: { host: '127.0.0.1', port: 6379, password: redis_password } },
          headers: security_headers, as: :json
      expect_success_response

      encrypted_row = AdminSetting.find_by(key: 'redis_config_password_encrypted')
      expect(encrypted_row).not_to be_nil
      expect(encrypted_row.value).not_to include(redis_password)
      expect(Security::CredentialEncryptionService.decrypt_value(encrypted_row.value)).to eq(redis_password)
    end

    it 'masks the password in both the PUT response and a subsequent GET' do
      allow(AdminSetting).to receive(:test_redis_connection).and_return(status: 'disconnected')

      put_response = nil
      put '/api/v1/admin_settings/infrastructure',
          params: { redis: { host: '127.0.0.1', port: 6379, password: redis_password } },
          headers: security_headers, as: :json
      put_response = response.parsed_body

      expect(put_response.dig('data', 'redis', 'password')).to eq('••••••••')
      expect(put_response.to_s).not_to include(redis_password)

      get '/api/v1/admin_settings/infrastructure', headers: read_headers, as: :json

      body = response.parsed_body
      expect(body.dig('data', 'redis', 'password')).to eq('••••••••')
      expect(body.to_s).not_to include(redis_password)
    end
  end

  describe 'PUT /api/v1/admin_settings/vault (vault_role_id / vault_secret_id)' do
    let(:role_id) { "role-test-#{SecureRandom.hex(4)}" }
    let(:secret_id) { "secret-test-#{SecureRandom.hex(4)}" }

    it 'never stores vault_role_id/vault_secret_id in the vault_config blob' do
      put '/api/v1/admin_settings/vault',
          params: { vault: { vault_addr: 'http://vault.example.internal:8200', vault_role_id: role_id, vault_secret_id: secret_id } },
          headers: security_headers, as: :json
      expect_success_response

      blob = AdminSetting.find_by(key: 'vault_config')
      expect(blob).not_to be_nil
      expect(blob.value).not_to include(role_id)
      expect(blob.value).not_to include(secret_id)
      # vault_addr is not a secret and stays in the blob.
      expect(blob.value).to include('vault.example.internal')
    end

    it 'stores vault_role_id and vault_secret_id encrypted, decryptable via Security::CredentialEncryptionService' do
      put '/api/v1/admin_settings/vault',
          params: { vault: { vault_role_id: role_id, vault_secret_id: secret_id } },
          headers: security_headers, as: :json
      expect_success_response

      role_row = AdminSetting.find_by(key: 'vault_role_id_encrypted')
      secret_row = AdminSetting.find_by(key: 'vault_secret_id_encrypted')

      expect(role_row).not_to be_nil
      expect(secret_row).not_to be_nil
      expect(role_row.value).not_to include(role_id)
      expect(secret_row.value).not_to include(secret_id)
      expect(Security::CredentialEncryptionService.decrypt_value(role_row.value)).to eq(role_id)
      expect(Security::CredentialEncryptionService.decrypt_value(secret_row.value)).to eq(secret_id)
    end

    it 'masks vault_role_id/vault_secret_id (last 4 chars only) in a subsequent GET' do
      put '/api/v1/admin_settings/vault',
          params: { vault: { vault_role_id: role_id, vault_secret_id: secret_id } },
          headers: security_headers, as: :json
      expect_success_response

      get '/api/v1/admin_settings/vault', headers: read_headers, as: :json

      body = response.parsed_body
      expect(body.dig('data', 'config', 'vault_role_id')).to eq("••••#{role_id[-4..]}")
      expect(body.dig('data', 'config', 'vault_secret_id')).to eq("••••#{secret_id[-4..]}")
      expect(body.to_s).not_to include(role_id)
      expect(body.to_s).not_to include(secret_id)
    end
  end

  describe 'the actual Redis/Vault connection still gets the real (decrypted) credential' do
    it 'Admin::SystemSettings.redis_config returns the decrypted password, not the mask or the blob-less value' do
      redis_password = "redis-real-secret-#{SecureRandom.hex(4)}"
      put '/api/v1/admin_settings/infrastructure',
          params: { redis: { host: '127.0.0.1', port: 6379, password: redis_password } },
          headers: security_headers, as: :json
      expect_success_response

      expect(Admin::SystemSettings.redis_config['password']).to eq(redis_password)
    end

    it 'Admin::SystemSettings.vault_config returns the decrypted role_id/secret_id' do
      role_id = "role-real-#{SecureRandom.hex(4)}"
      secret_id = "secret-real-#{SecureRandom.hex(4)}"
      put '/api/v1/admin_settings/vault',
          params: { vault: { vault_role_id: role_id, vault_secret_id: secret_id } },
          headers: security_headers, as: :json
      expect_success_response

      config = Admin::SystemSettings.vault_config
      expect(config['vault_role_id']).to eq(role_id)
      expect(config['vault_secret_id']).to eq(secret_id)
    end
  end
end
