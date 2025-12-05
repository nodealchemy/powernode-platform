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
        provider = described_class.create(storage_config)
        expect(provider).to be_a(StorageProviders::S3Storage)
      end
    end

    context 'with GCS storage' do
      let(:storage_config) { create(:file_storage, :gcs, account: account) }

      it 'creates GcsStorage provider' do
        provider = described_class.create(storage_config)
        expect(provider).to be_a(StorageProviders::GcsStorage)
      end
    end

    context 'with Azure storage' do
      let(:storage_config) { create(:file_storage, :azure, account: account) }

      it 'creates AzureStorage provider' do
        provider = described_class.create(storage_config)
        expect(provider).to be_a(StorageProviders::AzureStorage)
      end
    end

    context 'with unknown provider type' do
      let(:storage_config) do
        create(:file_storage, account: account, provider_type: 'unknown')
      end

      it 'raises error' do
        expect {
          described_class.create(storage_config)
        }.to raise_error(ArgumentError, /Unsupported storage provider/)
      end
    end
  end

  describe '.supported_providers' do
    it 'returns list of supported providers' do
      providers = described_class.supported_providers

      expect(providers).to include('local', 's3', 'gcs', 'azure')
      expect(providers).to be_a(Array)
    end
  end

  describe '.provider_info' do
    it 'returns provider information for local' do
      info = described_class.provider_info('local')

      expect(info[:name]).to eq('Local Filesystem')
      expect(info[:class]).to eq(StorageProviders::LocalStorage)
      expect(info[:required_config]).to include('root_path')
    end

    it 'returns provider information for S3' do
      info = described_class.provider_info('s3')

      expect(info[:name]).to eq('Amazon S3')
      expect(info[:class]).to eq(StorageProviders::S3Storage)
      expect(info[:required_config]).to include('bucket', 'region')
    end

    it 'returns nil for unknown provider' do
      info = described_class.provider_info('unknown')
      expect(info).to be_nil
    end
  end
end
