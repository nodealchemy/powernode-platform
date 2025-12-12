# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StorageProviderFactory, type: :service do
  let(:account) { create(:account) }

  describe '.create' do
    context 'with local storage' do
      let(:storage_config) { create(:file_storage, account: account, provider_type: 'local') }

      it 'creates LocalStorage provider' do
        provider = described_class.create(storage_config)
        expect(provider).to be_a(StorageProviders::LocalStorage)
      end
    end

    context 'with S3 storage' do
      let(:storage_config) { create(:file_storage, :s3, account: account) }

      it 'creates S3Storage provider' do
        # Mock the S3 provider initialization to avoid credential decryption and AWS client creation
        s3_provider_double = instance_double(StorageProviders::S3Storage)
        allow(StorageProviders::S3Storage).to receive(:new).and_return(s3_provider_double)

        provider = described_class.create(storage_config)
        expect(provider).to eq(s3_provider_double)
      end
    end

    context 'with unsupported provider type' do
      it 'raises UnsupportedProviderError for GCS' do
        # Build the storage config without saving to avoid model validation
        storage_config = build(:file_storage, account: account, provider_type: 'gcs')
        storage_config.instance_variable_set(:@new_record, false)
        allow(storage_config).to receive(:provider_type).and_return('gcs')

        expect {
          described_class.create(storage_config)
        }.to raise_error(StorageProviderFactory::UnsupportedProviderError, /Unsupported provider type/)
      end

      it 'raises UnsupportedProviderError for Azure' do
        storage_config = build(:file_storage, account: account, provider_type: 'azure')
        storage_config.instance_variable_set(:@new_record, false)
        allow(storage_config).to receive(:provider_type).and_return('azure')

        expect {
          described_class.create(storage_config)
        }.to raise_error(StorageProviderFactory::UnsupportedProviderError, /Unsupported provider type/)
      end

      it 'raises UnsupportedProviderError for unknown provider' do
        storage_config = build(:file_storage, account: account, provider_type: 'unknown')
        storage_config.instance_variable_set(:@new_record, false)
        allow(storage_config).to receive(:provider_type).and_return('unknown')

        expect {
          described_class.create(storage_config)
        }.to raise_error(StorageProviderFactory::UnsupportedProviderError, /Unsupported provider type/)
      end
    end
  end

  describe '.supported_providers' do
    it 'returns list of supported providers' do
      providers = described_class.supported_providers

      expect(providers).to include('local', 's3')
      expect(providers).to be_a(Array)
    end

    it 'includes only implemented provider types' do
      providers = described_class.supported_providers

      expect(providers).to contain_exactly('local', 's3')
    end
  end

  describe '.supported?' do
    it 'returns true for supported providers' do
      expect(described_class.supported?('local')).to be true
      expect(described_class.supported?('s3')).to be true
    end

    it 'returns false for unsupported providers' do
      expect(described_class.supported?('unknown')).to be false
      expect(described_class.supported?('dropbox')).to be false
      expect(described_class.supported?('gcs')).to be false
      expect(described_class.supported?('azure')).to be false
    end

    it 'is case insensitive' do
      expect(described_class.supported?('LOCAL')).to be true
      expect(described_class.supported?('S3')).to be true
    end
  end

  describe '.provider_capabilities' do
    it 'returns capabilities for local storage' do
      capabilities = described_class.provider_capabilities('local')

      expect(capabilities['multipart_upload']).to be false
      expect(capabilities['versioning']).to be true
      expect(capabilities['streaming']).to be true
      expect(capabilities['batch_operations']).to be true
    end

    it 'returns capabilities for S3 storage' do
      capabilities = described_class.provider_capabilities('s3')

      expect(capabilities['multipart_upload']).to be true
      expect(capabilities['resumable_upload']).to be true
      expect(capabilities['direct_upload']).to be true
      expect(capabilities['cdn']).to be true
      expect(capabilities['signed_urls']).to be true
      expect(capabilities['lifecycle_policies']).to be true
    end

    it 'returns default capabilities for unsupported provider' do
      capabilities = described_class.provider_capabilities('gcs')

      expect(capabilities['multipart_upload']).to be false
      expect(capabilities['versioning']).to be false
    end

    it 'returns default capabilities for unknown provider' do
      capabilities = described_class.provider_capabilities('unknown')

      expect(capabilities['multipart_upload']).to be false
      expect(capabilities['versioning']).to be false
    end
  end

  describe '.check_dependencies' do
    it 'returns available for local storage' do
      result = described_class.check_dependencies('local')

      expect(result[:available]).to be true
      expect(result[:missing]).to be_empty
    end

    it 'checks S3 dependencies' do
      result = described_class.check_dependencies('s3')

      expect(result).to have_key(:available)
      expect(result).to have_key(:missing)
    end

    it 'returns unavailable for unsupported provider' do
      result = described_class.check_dependencies('gcs')

      expect(result[:available]).to be false
      expect(result[:missing]).to include('Unknown provider type')
    end

    it 'returns unavailable for unknown provider' do
      result = described_class.check_dependencies('unknown')

      expect(result[:available]).to be false
      expect(result[:missing]).to include('Unknown provider type')
    end
  end

  describe '.get_provider_class' do
    it 'returns class name for valid provider' do
      expect(described_class.get_provider_class('local')).to eq('StorageProviders::LocalStorage')
      expect(described_class.get_provider_class('s3')).to eq('StorageProviders::S3Storage')
    end

    it 'raises error for invalid provider' do
      expect {
        described_class.get_provider_class('invalid')
      }.to raise_error(StorageProviderFactory::UnsupportedProviderError)
    end

    it 'raises error for removed providers' do
      expect {
        described_class.get_provider_class('gcs')
      }.to raise_error(StorageProviderFactory::UnsupportedProviderError)

      expect {
        described_class.get_provider_class('azure')
      }.to raise_error(StorageProviderFactory::UnsupportedProviderError)
    end

    it 'is case insensitive' do
      expect(described_class.get_provider_class('LOCAL')).to eq('StorageProviders::LocalStorage')
      expect(described_class.get_provider_class('S3')).to eq('StorageProviders::S3Storage')
    end
  end
end
