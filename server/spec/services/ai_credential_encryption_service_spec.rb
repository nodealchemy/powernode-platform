# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCredentialEncryptionService, type: :service do
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

    it 'uses application key management when no key provided' do
      service = described_class.new
      key_id = service.instance_variable_get(:@key_id)
      expect(key_id).to eq(described_class.current_key_id)
    end

    it 'generates unique salt when custom key provided' do
      service1 = described_class.new(encryption_key: 'a-strong-encryption-key-123')
      service2 = described_class.new(encryption_key: 'a-strong-encryption-key-456')

      salt1 = service1.instance_variable_get(:@salt)
      salt2 = service2.instance_variable_get(:@salt)

      expect(salt1).to be_present
      expect(salt2).to be_present
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

      it 'raises error for empty credentials' do
        expect {
          service.encrypt_credentials({})
        }.to raise_error(AiCredentialEncryptionService::EncryptionError, /cannot be empty/)
      end

      it 'raises error for nil credentials' do
        expect {
          service.encrypt_credentials(nil)
        }.to raise_error(AiCredentialEncryptionService::EncryptionError, /must be a Hash/)
      end
    end

    context 'error handling' do
      it 'raises error for non-hash input' do
        expect {
          service.encrypt_credentials('not a hash')
        }.to raise_error(AiCredentialEncryptionService::EncryptionError, /must be a Hash/)
      end
    end
  end

  describe '#decrypt_credentials' do
    let(:service) { described_class.new }

    context 'with valid encrypted data' do
      it 'decrypts OpenAI credentials correctly' do
        encrypted_data = service.encrypt_credentials(openai_credentials)
        decrypted_data = service.decrypt_credentials(encrypted_data)

        expect(decrypted_data['api_key']).to eq(openai_credentials[:api_key])
        expect(decrypted_data['organization_id']).to eq(openai_credentials[:organization_id])
      end

      it 'decrypts Anthropic credentials correctly' do
        encrypted_data = service.encrypt_credentials(anthropic_credentials)
        decrypted_data = service.decrypt_credentials(encrypted_data)

        expect(decrypted_data['api_key']).to eq(anthropic_credentials[:api_key])
      end

      it 'decrypts credentials with multiple fields' do
        multi_field_creds = {
          api_key: 'key123',
          base_url: 'https://api.example.com',
          organization: 'org-12345'
        }

        encrypted_data = service.encrypt_credentials(multi_field_creds)
        decrypted_data = service.decrypt_credentials(encrypted_data)

        # Keys are downcased during sanitization
        expect(decrypted_data['api_key']).to eq('key123')
        expect(decrypted_data['base_url']).to eq('https://api.example.com')
        expect(decrypted_data['organization']).to eq('org-12345')
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

      it 'raises error for nil input' do
        expect {
          service.decrypt_credentials(nil)
        }.to raise_error(AiCredentialEncryptionService::DecryptionError, /cannot be blank/)
      end

      it 'raises error for blank input' do
        expect {
          service.decrypt_credentials('')
        }.to raise_error(AiCredentialEncryptionService::DecryptionError, /cannot be blank/)
      end
    end
  end

  describe '#encrypt and #decrypt (simple value methods)' do
    let(:service) { described_class.new }

    it 'encrypts single values' do
      encrypted = service.encrypt('my-secret-value')

      expect(encrypted).to be_a(String)
      expect(encrypted).not_to include('my-secret-value')
    end

    it 'decrypts single values' do
      original = 'my-secret-value'
      encrypted = service.encrypt(original)
      decrypted = service.decrypt(encrypted)

      expect(decrypted).to eq(original)
    end

    it 'returns nil for blank values' do
      expect(service.encrypt(nil)).to be_nil
      expect(service.encrypt('')).to be_nil
      expect(service.decrypt(nil)).to be_nil
      expect(service.decrypt('')).to be_nil
    end

    it 'stores key_id for proper decryption' do
      encrypted = service.encrypt('test-value')
      wrapper = JSON.parse(Base64.decode64(encrypted))

      expect(wrapper['key_id']).to be_present
    end
  end

  describe 'class methods' do
    describe '.encrypt' do
      it 'encrypts credentials hash' do
        encrypted = described_class.encrypt(openai_credentials)

        expect(encrypted).to be_a(String)
        expect(encrypted).not_to include('sk-1234567890')
      end

      it 'raises error for non-hash input' do
        expect {
          described_class.encrypt('not a hash')
        }.to raise_error(AiCredentialEncryptionService::EncryptionError, /must be a Hash/)
      end
    end

    describe '.decrypt' do
      it 'decrypts encrypted credentials' do
        encrypted = described_class.encrypt(openai_credentials)
        decrypted = described_class.decrypt(encrypted)

        expect(decrypted['api_key']).to eq(openai_credentials[:api_key])
      end

      it 'raises error for invalid data' do
        expect {
          described_class.decrypt('invalid-data')
        }.to raise_error(AiCredentialEncryptionService::DecryptionError)
      end
    end

    describe '.valid_encrypted_credentials?' do
      it 'returns true for valid encrypted data' do
        encrypted = described_class.encrypt(openai_credentials)
        expect(described_class.valid_encrypted_credentials?(encrypted)).to be true
      end

      it 'returns false for invalid data' do
        expect(described_class.valid_encrypted_credentials?('invalid')).to be false
      end
    end

    describe '.current_key_id' do
      it 'returns current encryption key ID' do
        key_id = described_class.current_key_id
        expect(key_id).to be_a(String)
      end
    end

    describe '.get_encryption_key' do
      it 'returns encryption key for given ID' do
        key = described_class.get_encryption_key('default')
        expect(key).to be_a(String)
      end
    end

    describe '.generate_new_key' do
      it 'generates new encryption key' do
        key = described_class.generate_new_key
        expect(key).to be_a(String)
        expect(key.length).to be > 20
      end
    end
  end

  describe 'performance' do
    let(:service) { described_class.new }

    it 'encrypts credentials within acceptable time limits' do
      start_time = Time.current

      100.times do
        service.encrypt_credentials(openai_credentials)
      end

      elapsed = Time.current - start_time
      expect(elapsed).to be < 5.seconds
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
