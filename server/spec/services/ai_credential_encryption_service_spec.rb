# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCredentialEncryptionService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, :openai) }
  
  # Sample credential data for different providers
  let(:openai_credentials) do
    {
      api_key: 'sk-1234567890abcdef1234567890abcdef',
      organization_id: 'org-1234567890abcdef',
      model: 'gpt-3.5-turbo'
    }
  end

  let(:anthropic_credentials) do
    {
      api_key: 'sk-ant-api03-1234567890abcdef',
      model: 'claude-3-sonnet-20240229'
    }
  end

  let(:ollama_credentials) do
    {
      base_url: 'http://localhost:11434',
      model: 'llama2',
      headers: { 'X-Custom-Header' => 'value' }
    }
  end

  let(:sensitive_credentials) do
    {
      api_key: 'sk-very-secret-key',
      client_secret: 'super-secret-client-secret',
      private_key: '-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC...\n-----END PRIVATE KEY-----',
      oauth_token: 'oauth2-access-token-12345'
    }
  end

  describe '#initialize' do
    it 'initializes with proper encryption configuration' do
      service = described_class.new
      expect(service.instance_variable_get(:@encryption_key)).to be_present
      expect(service.instance_variable_get(:@cipher_algorithm)).to eq('aes-256-gcm')
    end

    it 'generates unique salt for each instance' do
      service1 = described_class.new
      service2 = described_class.new
      
      salt1 = service1.instance_variable_get(:@salt)
      salt2 = service2.instance_variable_get(:@salt)
      
      expect(salt1).not_to eq(salt2)
    end

    it 'validates encryption key strength' do
      expect {
        described_class.new(encryption_key: 'weak')
      }.to raise_error(AiCredentialEncryptionService::WeakEncryptionKeyError)
    end
  end

  describe '#encrypt_credentials' do
    let(:service) { described_class.new }

    context 'with OpenAI credentials' do
      it 'encrypts credentials successfully' do
        encrypted_data = service.encrypt_credentials(openai_credentials)
        
        expect(encrypted_data).to be_a(String)
        expect(encrypted_data).not_to include('sk-1234567890abcdef1234567890abcdef')
        expect(encrypted_data.length).to be > 100 # Encrypted data should be longer
      end

      it 'includes encryption metadata' do
        encrypted_data = service.encrypt_credentials(openai_credentials)
        
        # Should be base64 encoded JSON with metadata
        decoded = JSON.parse(Base64.decode64(encrypted_data))
        expect(decoded).to include('encrypted_data', 'iv', 'auth_tag', 'algorithm', 'timestamp')
      end

      it 'produces different output for same input' do
        encrypted1 = service.encrypt_credentials(openai_credentials)
        encrypted2 = service.encrypt_credentials(openai_credentials)
        
        expect(encrypted1).not_to eq(encrypted2) # Different IV each time
      end
    end

    context 'with Anthropic credentials' do
      it 'encrypts Anthropic-specific credentials' do
        encrypted_data = service.encrypt_credentials(anthropic_credentials)
        
        expect(encrypted_data).to be_a(String)
        expect(encrypted_data).not_to include('sk-ant-api03')
      end
    end

    context 'with Ollama credentials' do
      it 'encrypts local provider credentials' do
        encrypted_data = service.encrypt_credentials(ollama_credentials)
        
        expect(encrypted_data).not_to include('localhost:11434')
        expect(encrypted_data).not_to include('X-Custom-Header')
      end
    end

    context 'with sensitive data' do
      it 'encrypts private keys securely' do
        encrypted_data = service.encrypt_credentials(sensitive_credentials)
        
        expect(encrypted_data).not_to include('BEGIN PRIVATE KEY')
        expect(encrypted_data).not_to include('super-secret-client-secret')
      end

      it 'handles empty credentials' do
        expect {
          service.encrypt_credentials({})
        }.to raise_error(AiCredentialEncryptionService::InvalidCredentialsError)
      end

      it 'handles nil credentials' do
        expect {
          service.encrypt_credentials(nil)
        }.to raise_error(AiCredentialEncryptionService::InvalidCredentialsError)
      end
    end

    context 'error handling' do
      it 'raises error for non-hash input' do
        expect {
          service.encrypt_credentials('not a hash')
        }.to raise_error(AiCredentialEncryptionService::InvalidCredentialsError)
      end

      it 'raises error for credentials too large' do
        huge_credentials = { data: 'x' * 100_000 }
        
        expect {
          service.encrypt_credentials(huge_credentials)
        }.to raise_error(AiCredentialEncryptionService::CredentialsTooLargeError)
      end
    end
  end

  describe '#decrypt_credentials' do
    let(:service) { described_class.new }

    context 'with valid encrypted data' do
      it 'decrypts OpenAI credentials correctly' do
        encrypted_data = service.encrypt_credentials(openai_credentials)
        decrypted_data = service.decrypt_credentials(encrypted_data)
        
        expect(decrypted_data).to eq(openai_credentials.stringify_keys)
      end

      it 'decrypts Anthropic credentials correctly' do
        encrypted_data = service.encrypt_credentials(anthropic_credentials)
        decrypted_data = service.decrypt_credentials(encrypted_data)
        
        expect(decrypted_data).to eq(anthropic_credentials.stringify_keys)
      end

      it 'decrypts complex nested data' do
        complex_creds = {
          api_key: 'key123',
          config: {
            timeout: 30,
            retries: 3,
            headers: { 'Authorization' => 'Bearer token123' }
          }
        }
        
        encrypted_data = service.encrypt_credentials(complex_creds)
        decrypted_data = service.decrypt_credentials(encrypted_data)
        
        expect(decrypted_data['config']['headers']['Authorization']).to eq('Bearer token123')
      end
    end

    context 'with invalid encrypted data' do
      it 'raises error for corrupted data' do
        corrupted_data = 'not-valid-encrypted-data'
        
        expect {
          service.decrypt_credentials(corrupted_data)
        }.to raise_error(AiCredentialEncryptionService::DecryptionError)
      end

      it 'raises error for tampered data' do
        encrypted_data = service.encrypt_credentials(openai_credentials)
        tampered_data = encrypted_data[0..-5] + 'xxxx'
        
        expect {
          service.decrypt_credentials(tampered_data)
        }.to raise_error(AiCredentialEncryptionService::DecryptionError)
      end

      it 'raises error for data encrypted with different key' do
        other_service = described_class.new
        
        encrypted_data = other_service.encrypt_credentials(openai_credentials)
        
        expect {
          service.decrypt_credentials(encrypted_data)
        }.to raise_error(AiCredentialEncryptionService::DecryptionError)
      end

      it 'raises error for nil input' do
        expect {
          service.decrypt_credentials(nil)
        }.to raise_error(AiCredentialEncryptionService::DecryptionError)
      end
    end

    context 'with expired encrypted data' do
      it 'raises error for expired credentials' do
        service = described_class.new(credential_ttl: 1.second)
        encrypted_data = service.encrypt_credentials(openai_credentials)
        
        sleep(2) # Wait for expiration
        
        expect {
          service.decrypt_credentials(encrypted_data)
        }.to raise_error(AiCredentialEncryptionService::ExpiredCredentialsError)
      end
    end
  end

  describe '#rotate_encryption_key' do
    let(:service) { described_class.new }

    it 'rotates encryption key while maintaining access to old data' do
      encrypted_with_old_key = service.encrypt_credentials(openai_credentials)
      
      service.rotate_encryption_key
      
      # Should still be able to decrypt old data
      decrypted_data = service.decrypt_credentials(encrypted_with_old_key)
      expect(decrypted_data).to eq(openai_credentials.stringify_keys)
      
      # New encryptions should use new key
      encrypted_with_new_key = service.encrypt_credentials(anthropic_credentials)
      expect(encrypted_with_new_key).not_to eq(encrypted_with_old_key)
    end

    it 'maintains key history for decryption' do
      original_encrypted = service.encrypt_credentials(openai_credentials)
      
      3.times { service.rotate_encryption_key }
      
      # Should still decrypt with any historical key
      decrypted = service.decrypt_credentials(original_encrypted)
      expect(decrypted).to eq(openai_credentials.stringify_keys)
    end

    it 'limits key history to prevent memory bloat' do
      10.times { service.rotate_encryption_key }
      
      key_history = service.instance_variable_get(:@key_history)
      expect(key_history.size).to be <= 5 # Should limit history
    end
  end

  describe '#mask_sensitive_data' do
    let(:service) { described_class.new }

    it 'masks API keys in logs' do
      credentials = {
        api_key: 'sk-1234567890abcdef1234567890abcdef',
        model: 'gpt-3.5-turbo'
      }
      
      masked = service.mask_sensitive_data(credentials)
      
      expect(masked[:api_key]).to eq('sk-***...***cdef')
      expect(masked[:model]).to eq('gpt-3.5-turbo') # Non-sensitive unchanged
    end

    it 'masks various types of sensitive fields' do
      sensitive_data = {
        api_key: 'sk-1234567890abcdef',
        secret_key: 'secret123456789',
        password: 'mypassword123',
        token: 'bearer-token-12345',
        private_key: '-----BEGIN PRIVATE KEY-----\ndata\n-----END PRIVATE KEY-----'
      }
      
      masked = service.mask_sensitive_data(sensitive_data)
      
      expect(masked[:api_key]).to match(/sk-\*{3}\.\.\./)
      expect(masked[:secret_key]).to match(/\*{3}\.\.\./)
      expect(masked[:password]).to match(/\*{3}\.\.\./)
      expect(masked[:token]).to match(/\*{3}\.\.\./)
      expect(masked[:private_key]).to match(/\*{3}\.\.\./)
    end

    it 'handles nested sensitive data' do
      nested_data = {
        config: {
          auth: {
            api_key: 'sk-secret123',
            client_secret: 'very-secret'
          },
          timeout: 30
        }
      }
      
      masked = service.mask_sensitive_data(nested_data)
      
      expect(masked[:config][:auth][:api_key]).to match(/sk-\*{3}\.\.\./)
      expect(masked[:config][:auth][:client_secret]).to match(/\*{3}\.\.\./)
      expect(masked[:config][:timeout]).to eq(30)
    end
  end

  describe '#validate_credential_strength' do
    let(:service) { described_class.new }

    context 'API key validation' do
      it 'validates strong API keys' do
        strong_key = 'sk-' + ('a'..'z').to_a.sample(40).join
        result = service.validate_credential_strength({ api_key: strong_key })
        
        expect(result[:valid]).to be true
        expect(result[:strength_score]).to be > 0.8
      end

      it 'rejects weak API keys' do
        weak_key = 'sk-123'
        result = service.validate_credential_strength({ api_key: weak_key })
        
        expect(result[:valid]).to be false
        expect(result[:strength_score]).to be < 0.5
        expect(result[:warnings]).to include(/too short/i)
      end

      it 'rejects common patterns' do
        common_key = 'sk-test1234567890test1234567890'
        result = service.validate_credential_strength({ api_key: common_key })
        
        expect(result[:warnings]).to include(/common pattern/i)
      end
    end

    context 'private key validation' do
      it 'validates proper private key format' do
        valid_key = "-----BEGIN PRIVATE KEY-----\n#{'A' * 64}\n-----END PRIVATE KEY-----"
        result = service.validate_credential_strength({ private_key: valid_key })
        
        expect(result[:valid]).to be true
      end

      it 'rejects malformed private keys' do
        invalid_key = 'not-a-private-key'
        result = service.validate_credential_strength({ private_key: invalid_key })
        
        expect(result[:valid]).to be false
        expect(result[:warnings]).to include(/invalid format/i)
      end
    end
  end

  describe '#audit_credential_access' do
    let(:service) { described_class.new }
    let(:credential) { create(:ai_provider_credential, account: account, ai_provider: provider) }

    it 'logs credential access events' do
      expect {
        service.audit_credential_access(
          credential_id: credential.id,
          action: 'decrypt',
          user_id: account.users.first.id,
          ip_address: '192.168.1.1',
          user_agent: 'Test Agent'
        )
      }.to change { 
        service.instance_variable_get(:@audit_log)&.size || 0 
      }.by(1)
    end

    it 'includes comprehensive audit information' do
      service.audit_credential_access(
        credential_id: credential.id,
        action: 'encrypt',
        user_id: account.users.first.id,
        ip_address: '10.0.0.1'
      )
      
      audit_entries = service.instance_variable_get(:@audit_log)
      latest_entry = audit_entries.last
      
      expect(latest_entry).to include(
        :timestamp,
        :credential_id,
        :action,
        :user_id,
        :ip_address,
        :success
      )
    end

    it 'logs failed access attempts' do
      service.audit_credential_access(
        credential_id: credential.id,
        action: 'decrypt',
        user_id: account.users.first.id,
        success: false,
        error: 'Invalid key'
      )
      
      audit_entries = service.instance_variable_get(:@audit_log)
      failed_entry = audit_entries.last
      
      expect(failed_entry[:success]).to be false
      expect(failed_entry[:error]).to eq('Invalid key')
    end
  end

  describe '#generate_secure_backup' do
    let(:service) { described_class.new }

    it 'generates encrypted backup of all credentials' do
      credentials_batch = [
        { id: 1, data: openai_credentials },
        { id: 2, data: anthropic_credentials }
      ]
      
      backup = service.generate_secure_backup(credentials_batch)
      
      expect(backup).to include(
        :encrypted_data,
        :backup_metadata,
        :verification_hash,
        :timestamp
      )
    end

    it 'includes integrity verification' do
      credentials_batch = [{ id: 1, data: openai_credentials }]
      backup = service.generate_secure_backup(credentials_batch)
      
      # Verify backup integrity
      is_valid = service.verify_backup_integrity(backup)
      expect(is_valid).to be true
    end

    it 'protects backup with additional encryption layer' do
      credentials_batch = [{ id: 1, data: sensitive_credentials }]
      backup = service.generate_secure_backup(credentials_batch)
      
      # Backup should not contain plaintext sensitive data
      backup_string = backup.to_json
      expect(backup_string).not_to include('super-secret-client-secret')
      expect(backup_string).not_to include('BEGIN PRIVATE KEY')
    end
  end

  describe '#restore_from_backup' do
    let(:service) { described_class.new }

    it 'restores credentials from valid backup' do
      original_batch = [
        { id: 1, data: openai_credentials },
        { id: 2, data: anthropic_credentials }
      ]
      
      backup = service.generate_secure_backup(original_batch)
      restored = service.restore_from_backup(backup)
      
      expect(restored.size).to eq(2)
      expect(restored.first[:data]).to eq(openai_credentials.stringify_keys)
    end

    it 'validates backup integrity before restoration' do
      backup = {
        encrypted_data: 'corrupted-data',
        verification_hash: 'invalid-hash',
        timestamp: Time.current
      }
      
      expect {
        service.restore_from_backup(backup)
      }.to raise_error(AiCredentialEncryptionService::BackupCorruptedError)
    end
  end

  describe '#performance_benchmarks' do
    let(:service) { described_class.new }

    it 'encrypts credentials within acceptable time limits' do
      start_time = Time.current
      
      100.times do
        service.encrypt_credentials(openai_credentials)
      end
      
      elapsed = Time.current - start_time
      expect(elapsed).to be < 5.seconds # Should be fast
    end

    it 'decrypts credentials efficiently' do
      encrypted_batch = 100.times.map do
        service.encrypt_credentials(openai_credentials)
      end
      
      start_time = Time.current
      
      encrypted_batch.each do |encrypted|
        service.decrypt_credentials(encrypted)
      end
      
      elapsed = Time.current - start_time
      expect(elapsed).to be < 3.seconds
    end

    it 'handles concurrent encryption/decryption' do
      threads = 10.times.map do
        Thread.new do
          10.times do
            encrypted = service.encrypt_credentials(openai_credentials)
            decrypted = service.decrypt_credentials(encrypted)
            expect(decrypted['api_key']).to eq(openai_credentials[:api_key])
          end
        end
      end
      
      threads.each(&:join)
      # If we get here without errors, concurrency handling works
    end
  end

  describe 'private methods' do
    let(:service) { described_class.new }

    describe '#generate_encryption_key' do
      it 'generates cryptographically secure keys' do
        key1 = service.send(:generate_encryption_key)
        key2 = service.send(:generate_encryption_key)
        
        expect(key1).not_to eq(key2)
        expect(key1.length).to eq(32) # 256 bits
        expect(key2.length).to eq(32)
      end
    end

    describe '#derive_key_from_password' do
      it 'derives consistent keys from same password' do
        password = 'test-password-123'
        salt = 'fixed-salt-for-test'
        
        key1 = service.send(:derive_key_from_password, password, salt)
        key2 = service.send(:derive_key_from_password, password, salt)
        
        expect(key1).to eq(key2)
        expect(key1.length).to eq(32)
      end

      it 'produces different keys for different passwords' do
        salt = 'same-salt'
        
        key1 = service.send(:derive_key_from_password, 'password1', salt)
        key2 = service.send(:derive_key_from_password, 'password2', salt)
        
        expect(key1).not_to eq(key2)
      end
    end
  end
end