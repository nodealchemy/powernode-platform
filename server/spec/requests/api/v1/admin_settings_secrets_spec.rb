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

    # fc-38 review item #1: the GET response never returns any part of the
    # secret (no last-4 characters either) — just "" plus a
    # password_configured flag, so the UI can say "configured" without ever
    # holding a redisplayable fragment of the real value.
    it 'never returns any part of the password in the PUT response or a subsequent GET, only a password_configured flag' do
      allow(AdminSetting).to receive(:test_redis_connection).and_return(status: 'disconnected')

      put '/api/v1/admin_settings/infrastructure',
          params: { redis: { host: '127.0.0.1', port: 6379, password: redis_password } },
          headers: security_headers, as: :json
      put_response = response.parsed_body

      expect(put_response.dig('data', 'redis', 'password')).to eq('')
      expect(put_response.dig('data', 'redis', 'password_configured')).to be(true)
      expect(put_response.to_s).not_to include(redis_password)

      get '/api/v1/admin_settings/infrastructure', headers: read_headers, as: :json

      body = response.parsed_body
      expect(body.dig('data', 'redis', 'password')).to eq('')
      expect(body.dig('data', 'redis', 'password_configured')).to be(true)
      expect(body.to_s).not_to include(redis_password)
    end

    # fc-38 review item #1 (HIGH), the actual regression: since the GET
    # response used to echo back the literal 8-dot mask, and the write side
    # only skipped a value EQUAL to that exact mask, resubmitting the loaded
    # (masked) value on an unrelated save silently overwrote the real
    # password with 8 literal bullet characters. The GET response no longer
    # returns a mask to resubmit at all, but this pins the server-side
    # defense independently: a mask-shaped value must never overwrite a real
    # saved password.
    it 'saving host alone (without resending password) preserves the previously saved password' do
      put '/api/v1/admin_settings/infrastructure',
          params: { redis: { host: '127.0.0.1', port: 6379, password: redis_password } },
          headers: security_headers, as: :json
      expect_success_response

      put '/api/v1/admin_settings/infrastructure',
          params: { redis: { host: '10.0.0.5', port: 6379 } },
          headers: security_headers, as: :json
      expect_success_response

      expect(Admin::SystemSettings.redis_config['password']).to eq(redis_password)
      expect(AdminSetting.redis_config['host']).to eq('10.0.0.5')
    end

    it 'a mask-shaped password value ("••••••••") is ignored, not saved as the literal password' do
      put '/api/v1/admin_settings/infrastructure',
          params: { redis: { host: '127.0.0.1', port: 6379, password: redis_password } },
          headers: security_headers, as: :json
      expect_success_response

      put '/api/v1/admin_settings/infrastructure',
          params: { redis: { host: '127.0.0.1', port: 6379, password: '••••••••' } },
          headers: security_headers, as: :json
      expect_success_response

      expect(Admin::SystemSettings.redis_config['password']).to eq(redis_password)
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

    # fc-38 review item #1: no last-4 characters either — "" plus a
    # <field>_configured flag, matching the redis fix.
    it 'never returns any part of vault_role_id/vault_secret_id in a subsequent GET, only *_configured flags' do
      put '/api/v1/admin_settings/vault',
          params: { vault: { vault_role_id: role_id, vault_secret_id: secret_id } },
          headers: security_headers, as: :json
      expect_success_response

      get '/api/v1/admin_settings/vault', headers: read_headers, as: :json

      body = response.parsed_body
      expect(body.dig('data', 'config', 'vault_role_id')).to eq('')
      expect(body.dig('data', 'config', 'vault_role_id_configured')).to be(true)
      expect(body.dig('data', 'config', 'vault_secret_id')).to eq('')
      expect(body.dig('data', 'config', 'vault_secret_id_configured')).to be(true)
      expect(body.to_s).not_to include(role_id)
      expect(body.to_s).not_to include(secret_id)
    end

    # fc-38 review item #1 (HIGH), the actual regression: the old write-side
    # check only skipped a role_id/secret_id EQUAL to the redis-style
    # "••••••••" (8 dots), never the vault-style "••••<last4>" mask the GET
    # response actually returned — so resubmitting the loaded (masked) value
    # to save vault_addr alone silently overwrote BOTH real AppRole
    # credentials with the 8-character display mask.
    it 'saving vault_addr alone (without resending role_id/secret_id) preserves both previously saved credentials' do
      put '/api/v1/admin_settings/vault',
          params: { vault: { vault_addr: 'http://vault.example.internal:8200', vault_role_id: role_id, vault_secret_id: secret_id } },
          headers: security_headers, as: :json
      expect_success_response

      put '/api/v1/admin_settings/vault',
          params: { vault: { vault_addr: 'http://vault.updated.internal:8200' } },
          headers: security_headers, as: :json
      expect_success_response

      config = Admin::SystemSettings.vault_config
      expect(config['vault_addr']).to eq('http://vault.updated.internal:8200')
      expect(config['vault_role_id']).to eq(role_id)
      expect(config['vault_secret_id']).to eq(secret_id)
    end

    it 'a mask-shaped value ("••••xxxx") is ignored for both vault_role_id and vault_secret_id' do
      put '/api/v1/admin_settings/vault',
          params: { vault: { vault_role_id: role_id, vault_secret_id: secret_id } },
          headers: security_headers, as: :json
      expect_success_response

      put '/api/v1/admin_settings/vault',
          params: { vault: { vault_role_id: '••••abcd', vault_secret_id: '••••wxyz' } },
          headers: security_headers, as: :json
      expect_success_response

      config = Admin::SystemSettings.vault_config
      expect(config['vault_role_id']).to eq(role_id)
      expect(config['vault_secret_id']).to eq(secret_id)
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
