# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Security::CredentialEncryptionService do
  describe '.encrypt' do
    context 'with valid credentials' do
      let(:credentials) { { api_key: 'test_key_123', token: 'secret_token' } }

      it 'encrypts credentials hash' do
        encrypted = described_class.encrypt(credentials)

        expect(encrypted).to be_present
        expect(encrypted).not_to include('test_key_123')
        expect(encrypted).not_to include('secret_token')
      end

      it 'returns base64 encoded string' do
        encrypted = described_class.encrypt(credentials)

        expect { Base64.strict_decode64(encrypted) }.not_to raise_error
      end

      it 'includes version and key_id in wrapper' do
        encrypted = described_class.encrypt(credentials)
        wrapper = JSON.parse(Base64.strict_decode64(encrypted))

        expect(wrapper['version']).to eq('v2')
        expect(wrapper['key_id']).to be_present
        expect(wrapper['encrypted_data']).to be_present
        expect(wrapper['created_at']).to be_present
      end
    end

    context 'with namespace' do
      let(:credentials) { { api_key: 'namespaced_key' } }

      it 'includes namespace in wrapper' do
        encrypted = described_class.encrypt(credentials, namespace: 'mcp')
        wrapper = JSON.parse(Base64.strict_decode64(encrypted))

        expect(wrapper['namespace']).to eq('mcp')
      end

      it 'produces different results for different namespaces' do
        encrypted_mcp = described_class.encrypt(credentials, namespace: 'mcp')
        encrypted_storage = described_class.encrypt(credentials, namespace: 'storage')

        # Encrypted payloads will differ due to random IV
        wrapper_mcp = JSON.parse(Base64.strict_decode64(encrypted_mcp))
        wrapper_storage = JSON.parse(Base64.strict_decode64(encrypted_storage))

        expect(wrapper_mcp['namespace']).to eq('mcp')
        expect(wrapper_storage['namespace']).to eq('storage')
      end
    end

    context 'with invalid input' do
      it 'raises EncryptionError for non-hash input' do
        expect { described_class.encrypt('string') }
          .to raise_error(Security::CredentialEncryptionService::EncryptionError, /Credentials must be a Hash/)
      end

      it 'raises EncryptionError for empty hash' do
        expect { described_class.encrypt({}) }
          .to raise_error(Security::CredentialEncryptionService::EncryptionError, /Credentials cannot be empty/)
      end

      it 'raises EncryptionError for array input' do
        expect { described_class.encrypt([ 1, 2, 3 ]) }
          .to raise_error(Security::CredentialEncryptionService::EncryptionError, /Credentials must be a Hash/)
      end
    end
  end

  describe '.decrypt' do
    let(:credentials) { { 'api_key' => 'test_key_123', 'token' => 'secret_token' } }

    context 'with valid encrypted credentials' do
      it 'decrypts to original hash' do
        encrypted = described_class.encrypt(credentials)
        decrypted = described_class.decrypt(encrypted)

        expect(decrypted).to eq(credentials)
      end

      it 'handles symbol keys by converting to strings' do
        original = { api_key: 'key', secret: 'value' }
        encrypted = described_class.encrypt(original)
        decrypted = described_class.decrypt(encrypted)

        expect(decrypted).to eq({ 'api_key' => 'key', 'secret' => 'value' })
      end
    end

    context 'with namespace' do
      it 'decrypts with matching namespace' do
        encrypted = described_class.encrypt(credentials, namespace: 'mcp')
        decrypted = described_class.decrypt(encrypted, namespace: 'mcp')

        expect(decrypted).to eq(credentials)
      end

      it 'raises error for namespace mismatch' do
        encrypted = described_class.encrypt(credentials, namespace: 'mcp')

        expect { described_class.decrypt(encrypted, namespace: 'storage') }
          .to raise_error(Security::CredentialEncryptionService::DecryptionError, /Namespace mismatch/)
      end

      it 'decrypts without namespace if stored without namespace' do
        encrypted = described_class.encrypt(credentials)
        decrypted = described_class.decrypt(encrypted, namespace: nil)

        expect(decrypted).to eq(credentials)
      end
    end

    context 'with invalid input' do
      it 'raises ArgumentError for blank input' do
        expect { described_class.decrypt('') }
          .to raise_error(ArgumentError, 'Encrypted credentials cannot be blank')
      end

      it 'raises DecryptionError for invalid base64' do
        expect { described_class.decrypt('not_base64!@#') }
          .to raise_error(Security::CredentialEncryptionService::DecryptionError)
      end

      it 'raises DecryptionError for invalid JSON in wrapper' do
        invalid = Base64.strict_encode64('not json')

        expect { described_class.decrypt(invalid) }
          .to raise_error(Security::CredentialEncryptionService::DecryptionError)
      end

      it 'raises DecryptionError for unsupported version' do
        wrapper = {
          version: 'v99',
          key_id: 'default',
          encrypted_data: 'data'
        }
        encrypted = Base64.strict_encode64(wrapper.to_json)

        expect { described_class.decrypt(encrypted) }
          .to raise_error(Security::CredentialEncryptionService::DecryptionError, /Unsupported encryption version/)
      end
    end
  end

  describe '.encrypt_value / .decrypt_value' do
    it 'encrypts and decrypts a single value' do
      value = 'my_secret_token'
      encrypted = described_class.encrypt_value(value)
      decrypted = described_class.decrypt_value(encrypted)

      expect(decrypted).to eq(value)
    end

    it 'returns nil for blank value' do
      expect(described_class.encrypt_value('')).to be_nil
      expect(described_class.encrypt_value(nil)).to be_nil
    end

    it 'works with namespace' do
      value = 'oauth_access_token'
      encrypted = described_class.encrypt_value(value, namespace: 'mcp')
      decrypted = described_class.decrypt_value(encrypted, namespace: 'mcp')

      expect(decrypted).to eq(value)
    end

    it 'decrypt_value returns nil for blank input' do
      expect(described_class.decrypt_value('')).to be_nil
      expect(described_class.decrypt_value(nil)).to be_nil
    end
  end

  describe '.valid_encrypted_credentials?' do
    let(:credentials) { { api_key: 'test' } }

    it 'returns true for valid encrypted credentials' do
      encrypted = described_class.encrypt(credentials)

      expect(described_class.valid_encrypted_credentials?(encrypted)).to be true
    end

    it 'returns false for invalid encrypted credentials' do
      expect(described_class.valid_encrypted_credentials?('invalid')).to be false
    end

    it 'returns false for blank input' do
      expect(described_class.valid_encrypted_credentials?('')).to be false
    end

    it 'validates with namespace' do
      encrypted = described_class.encrypt(credentials, namespace: 'mcp')

      expect(described_class.valid_encrypted_credentials?(encrypted, namespace: 'mcp')).to be true
      expect(described_class.valid_encrypted_credentials?(encrypted, namespace: 'other')).to be false
    end
  end

  describe '.encrypted_with_current_key?' do
    let(:credentials) { { api_key: 'test' } }

    it 'returns true for freshly encrypted credentials' do
      encrypted = described_class.encrypt(credentials)

      expect(described_class.encrypted_with_current_key?(encrypted)).to be true
    end

    it 'returns false for blank input' do
      expect(described_class.encrypted_with_current_key?('')).to be false
      expect(described_class.encrypted_with_current_key?(nil)).to be false
    end

    it 'returns false for invalid input' do
      expect(described_class.encrypted_with_current_key?('invalid')).to be false
    end
  end

  describe '.current_key_id' do
    it 'returns default when no key configured' do
      expect(described_class.current_key_id).to eq('default')
    end

    it 'accepts namespace parameter' do
      expect(described_class.current_key_id('mcp')).to eq('default')
    end
  end

  describe '.available_keys' do
    it 'returns array with default when no keys configured' do
      expect(described_class.available_keys).to eq([ 'default' ])
    end

    it 'accepts namespace parameter' do
      expect(described_class.available_keys('mcp')).to eq([ 'default' ])
    end
  end

  describe '.key_rotation_needed?' do
    let(:credentials) { { api_key: 'test' } }

    it 'returns true for blank input' do
      expect(described_class.key_rotation_needed?('')).to be true
    end

    it 'returns false for freshly encrypted credentials' do
      encrypted = described_class.encrypt(credentials)

      expect(described_class.key_rotation_needed?(encrypted)).to be false
    end
  end

  describe '.rotate_encryption' do
    let(:credentials) { { 'api_key' => 'test_key' } }

    it 're-encrypts credentials' do
      original_encrypted = described_class.encrypt(credentials)
      rotated = described_class.rotate_encryption(original_encrypted)

      expect(rotated).not_to eq(original_encrypted)
      expect(described_class.decrypt(rotated)).to eq(credentials)
    end

    it 'maintains namespace during rotation' do
      encrypted = described_class.encrypt(credentials, namespace: 'mcp')
      rotated = described_class.rotate_encryption(encrypted, namespace: 'mcp')
      wrapper = JSON.parse(Base64.strict_decode64(rotated))

      expect(wrapper['namespace']).to eq('mcp')
    end
  end

  describe '.generate_new_key' do
    it 'generates a valid base64 encoded key' do
      key = described_class.generate_new_key

      expect(key).to be_present
      expect { Base64.decode64(key) }.not_to raise_error
    end

    it 'generates 32-byte keys' do
      key = described_class.generate_new_key
      decoded = Base64.decode64(key)

      expect(decoded.bytesize).to eq(32)
    end

    it 'generates unique keys each time' do
      key1 = described_class.generate_new_key
      key2 = described_class.generate_new_key

      expect(key1).not_to eq(key2)
    end
  end

  describe 'encryption security' do
    let(:credentials) { { api_key: 'sensitive_data' } }

    it 'uses AES-256-GCM' do
      encrypted = described_class.encrypt(credentials)

      # The encrypted data should contain IV (12 bytes) + auth tag (16 bytes) + ciphertext
      wrapper = JSON.parse(Base64.strict_decode64(encrypted))
      encrypted_data = Base64.strict_decode64(wrapper['encrypted_data'])

      # IV (12) + Auth Tag (16) + at least some ciphertext
      expect(encrypted_data.bytesize).to be > 28
    end

    it 'produces different ciphertext for same input (random IV)' do
      encrypted1 = described_class.encrypt(credentials)
      encrypted2 = described_class.encrypt(credentials)

      wrapper1 = JSON.parse(Base64.strict_decode64(encrypted1))
      wrapper2 = JSON.parse(Base64.strict_decode64(encrypted2))

      expect(wrapper1['encrypted_data']).not_to eq(wrapper2['encrypted_data'])
    end
  end

  describe 'version compatibility' do
    it 'supports v1 version for backwards compatibility' do
      # v1 format (legacy Ai::CredentialEncryptionService format)
      legacy_wrapper = {
        version: 'v1',
        key_id: 'default',
        encrypted_data: nil,
        created_at: Time.current.to_i
      }

      # Just verify version validation accepts v1
      expect { described_class.send(:validate_version, 'v1') }.not_to raise_error
    end

    it 'supports v2 version' do
      expect { described_class.send(:validate_version, 'v2') }.not_to raise_error
    end
  end

  # Production-hub credential-encryption key sourcing: a self-hosted pivot-boot
  # hub (ops-hub) has NO Rails credentials file (config/credentials.yml.enc +
  # master.key are gitignored, never shipped), so the key comes from an explicit
  # env var that rails-start.sh generates + persists. See #get_encryption_key /
  # #env_encryption_key.
  describe 'production env-provided encryption key' do
    let(:credentials) { { 'api_key' => 'prod_secret', 'token' => 'prod_token' } }
    let(:env_key) { described_class.generate_new_key } # base64 of 32 random bytes

    before do
      # Simulate production with an EMPTY Rails credentials file (exactly ops-hub).
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rails.application.credentials).to receive(:dig).and_return(nil)
    end

    context 'when the credential-encryption env key is present' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('CREDENTIAL_ENCRYPTION_KEY_DEFAULT').and_return(env_key)
      end

      it 'encrypts and decrypts round-trip using the env key' do
        encrypted = described_class.encrypt(credentials)
        expect(encrypted).to be_present
        expect(encrypted).not_to include('prod_secret')
        expect(described_class.decrypt(encrypted)).to eq(credentials)
      end

      it 'round-trips a namespaced (git) credential off the global env key' do
        encrypted = described_class.encrypt(credentials, namespace: 'git')
        expect(described_class.decrypt(encrypted, namespace: 'git')).to eq(credentials)
      end
    end

    context 'when NO credential-encryption env key is present (fail-closed)' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('CREDENTIAL_ENCRYPTION_KEY_DEFAULT').and_return(nil)
        allow(ENV).to receive(:[]).with('CREDENTIAL_ENCRYPTION_KEY_GIT_DEFAULT').and_return(nil)
      end

      it 'raises rather than encrypting with a derived/weak key' do
        expect { described_class.encrypt(credentials) }
          .to raise_error(Security::CredentialEncryptionService::EncryptionError, /Encryption key 'default' not found/)
      end

      it 'also fails closed for a namespaced credential' do
        expect { described_class.encrypt(credentials, namespace: 'git') }
          .to raise_error(Security::CredentialEncryptionService::EncryptionError, /Encryption key 'default' not found/)
      end
    end

    context 'namespace-scoped env key precedence' do
      let(:global_key) { described_class.generate_new_key }
      let(:scoped_key) { described_class.generate_new_key }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('CREDENTIAL_ENCRYPTION_KEY_DEFAULT').and_return(global_key)
        allow(ENV).to receive(:[]).with('CREDENTIAL_ENCRYPTION_KEY_GIT_DEFAULT').and_return(scoped_key)
      end

      it 'prefers the namespace-scoped key over the global one' do
        encrypted = described_class.encrypt(credentials, namespace: 'git')
        # Payload was made with the SCOPED key; remove it so only the global
        # key remains — decryption must then fail (proving the scoped key won).
        allow(ENV).to receive(:[]).with('CREDENTIAL_ENCRYPTION_KEY_GIT_DEFAULT').and_return(nil)
        expect { described_class.decrypt(encrypted, namespace: 'git') }
          .to raise_error(Security::CredentialEncryptionService::DecryptionError)
      end
    end
  end

  # Guards that the DEV/TEST path is unchanged after adding the production
  # env-key source: with empty credentials and no env key, a non-production
  # process still encrypts via the deterministic secret_key_base-derived fallback.
  describe 'dev/test fallback remains intact' do
    let(:credentials) { { 'api_key' => 'dev_secret' } }

    before do
      allow(Rails.application.credentials).to receive(:dig).and_return(nil)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('CREDENTIAL_ENCRYPTION_KEY_DEFAULT').and_return(nil)
    end

    it 'still round-trips without any credentials or env key (not production)' do
      expect(Rails.env.production?).to be(false)
      encrypted = described_class.encrypt(credentials)
      expect(described_class.decrypt(encrypted)).to eq(credentials)
    end
  end
end
