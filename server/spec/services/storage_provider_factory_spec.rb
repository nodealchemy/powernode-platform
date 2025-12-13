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
        s3_provider_double = instance_double(StorageProviders::S3Storage)
        allow(StorageProviders::S3Storage).to receive(:new).and_return(s3_provider_double)

        provider = described_class.create(storage_config)
        expect(provider).to eq(s3_provider_double)
      end
    end

    context 'with GCS storage' do
      it 'creates GcsStorage provider when class exists' do
        storage_config = build(:file_storage, account: account, provider_type: 'gcs')
        storage_config.instance_variable_set(:@new_record, false)
        allow(storage_config).to receive(:provider_type).and_return('gcs')

        gcs_provider_double = double('GcsStorage')
        gcs_class = Class.new do
          define_method(:initialize) { |*_args| }
        end
        stub_const('StorageProviders::GcsStorage', gcs_class)
        allow(gcs_class).to receive(:new).and_return(gcs_provider_double)

        provider = described_class.create(storage_config)
        expect(provider).to eq(gcs_provider_double)
      end
    end

    context 'with Azure storage' do
      it 'creates AzureStorage provider when class exists' do
        storage_config = build(:file_storage, account: account, provider_type: 'azure')
        storage_config.instance_variable_set(:@new_record, false)
        allow(storage_config).to receive(:provider_type).and_return('azure')

        azure_provider_double = double('AzureStorage')
        azure_class = Class.new do
          define_method(:initialize) { |*_args| }
        end
        stub_const('StorageProviders::AzureStorage', azure_class)
        allow(azure_class).to receive(:new).and_return(azure_provider_double)

        provider = described_class.create(storage_config)
        expect(provider).to eq(azure_provider_double)
      end
    end

    context 'with NFS storage' do
      it 'creates NfsStorage provider when class exists' do
        storage_config = build(:file_storage, account: account, provider_type: 'nfs')
        storage_config.instance_variable_set(:@new_record, false)
        allow(storage_config).to receive(:provider_type).and_return('nfs')

        nfs_provider_double = double('NfsStorage')
        nfs_class = Class.new do
          define_method(:initialize) { |*_args| }
        end
        stub_const('StorageProviders::NfsStorage', nfs_class)
        allow(nfs_class).to receive(:new).and_return(nfs_provider_double)

        provider = described_class.create(storage_config)
        expect(provider).to eq(nfs_provider_double)
      end
    end

    context 'with SMB storage' do
      it 'creates SmbStorage provider when class exists' do
        storage_config = build(:file_storage, account: account, provider_type: 'smb')
        storage_config.instance_variable_set(:@new_record, false)
        allow(storage_config).to receive(:provider_type).and_return('smb')

        smb_provider_double = double('SmbStorage')
        smb_class = Class.new do
          define_method(:initialize) { |*_args| }
        end
        stub_const('StorageProviders::SmbStorage', smb_class)
        allow(smb_class).to receive(:new).and_return(smb_provider_double)

        provider = described_class.create(storage_config)
        expect(provider).to eq(smb_provider_double)
      end
    end

    context 'with S3-compatible providers' do
      %w[backblaze_b2 digitalocean_spaces cloudflare_r2 minio wasabi].each do |provider_type|
        it "creates S3Storage provider for #{provider_type}" do
          storage_config = build(:file_storage, account: account, provider_type: provider_type)
          storage_config.instance_variable_set(:@new_record, false)
          allow(storage_config).to receive(:provider_type).and_return(provider_type)

          s3_provider_double = instance_double(StorageProviders::S3Storage)
          allow(StorageProviders::S3Storage).to receive(:new).and_return(s3_provider_double)

          provider = described_class.create(storage_config)
          expect(provider).to eq(s3_provider_double)
        end
      end
    end

    context 'with unsupported provider type' do
      it 'raises UnsupportedProviderError for unknown provider' do
        storage_config = build(:file_storage, account: account, provider_type: 'unknown')
        storage_config.instance_variable_set(:@new_record, false)
        allow(storage_config).to receive(:provider_type).and_return('unknown')

        expect {
          described_class.create(storage_config)
        }.to raise_error(StorageProviderFactory::UnsupportedProviderError, /Unsupported provider type/)
      end

      it 'raises UnsupportedProviderError for dropbox' do
        storage_config = build(:file_storage, account: account, provider_type: 'dropbox')
        storage_config.instance_variable_set(:@new_record, false)
        allow(storage_config).to receive(:provider_type).and_return('dropbox')

        expect {
          described_class.create(storage_config)
        }.to raise_error(StorageProviderFactory::UnsupportedProviderError, /Unsupported provider type/)
      end
    end
  end

  describe '.supported_providers' do
    it 'returns list of supported providers' do
      providers = described_class.supported_providers

      expect(providers).to include('local', 's3', 'gcs', 'azure', 'nfs', 'smb')
      expect(providers).to be_a(Array)
    end

    it 'includes all cloud storage providers' do
      providers = described_class.supported_providers

      expect(providers).to include(
        'local', 's3', 'gcs', 'azure', 'nfs', 'smb',
        'backblaze_b2', 'digitalocean_spaces', 'cloudflare_r2', 'minio', 'wasabi'
      )
    end

    it 'returns 11 supported providers' do
      expect(described_class.supported_providers.length).to eq(11)
    end
  end

  describe '.supported?' do
    it 'returns true for core providers' do
      expect(described_class.supported?('local')).to be true
      expect(described_class.supported?('s3')).to be true
      expect(described_class.supported?('gcs')).to be true
      expect(described_class.supported?('azure')).to be true
    end

    it 'returns true for network filesystem providers' do
      expect(described_class.supported?('nfs')).to be true
      expect(described_class.supported?('smb')).to be true
    end

    it 'returns true for S3-compatible providers' do
      expect(described_class.supported?('backblaze_b2')).to be true
      expect(described_class.supported?('digitalocean_spaces')).to be true
      expect(described_class.supported?('cloudflare_r2')).to be true
      expect(described_class.supported?('minio')).to be true
      expect(described_class.supported?('wasabi')).to be true
    end

    it 'returns false for unsupported providers' do
      expect(described_class.supported?('unknown')).to be false
      expect(described_class.supported?('dropbox')).to be false
      expect(described_class.supported?('ftp')).to be false
    end

    it 'is case insensitive' do
      expect(described_class.supported?('LOCAL')).to be true
      expect(described_class.supported?('S3')).to be true
      expect(described_class.supported?('GCS')).to be true
      expect(described_class.supported?('AZURE')).to be true
      expect(described_class.supported?('NFS')).to be true
      expect(described_class.supported?('SMB')).to be true
    end
  end

  describe '.s3_compatible?' do
    it 'returns true for S3-compatible providers' do
      expect(described_class.s3_compatible?('backblaze_b2')).to be true
      expect(described_class.s3_compatible?('digitalocean_spaces')).to be true
      expect(described_class.s3_compatible?('cloudflare_r2')).to be true
      expect(described_class.s3_compatible?('minio')).to be true
      expect(described_class.s3_compatible?('wasabi')).to be true
    end

    it 'returns false for native providers' do
      expect(described_class.s3_compatible?('local')).to be false
      expect(described_class.s3_compatible?('s3')).to be false
      expect(described_class.s3_compatible?('gcs')).to be false
      expect(described_class.s3_compatible?('azure')).to be false
      expect(described_class.s3_compatible?('nfs')).to be false
      expect(described_class.s3_compatible?('smb')).to be false
    end
  end

  describe '.network_filesystem?' do
    it 'returns true for network filesystem providers' do
      expect(described_class.network_filesystem?('nfs')).to be true
      expect(described_class.network_filesystem?('smb')).to be true
    end

    it 'returns false for non-network providers' do
      expect(described_class.network_filesystem?('local')).to be false
      expect(described_class.network_filesystem?('s3')).to be false
      expect(described_class.network_filesystem?('gcs')).to be false
      expect(described_class.network_filesystem?('azure')).to be false
      expect(described_class.network_filesystem?('backblaze_b2')).to be false
    end
  end

  describe '.provider_info' do
    it 'returns info for known providers' do
      info = described_class.provider_info('s3')

      expect(info[:name]).to eq('Amazon S3')
      expect(info[:description]).to be_present
    end

    it 'returns info for S3-compatible providers' do
      info = described_class.provider_info('cloudflare_r2')

      expect(info[:name]).to eq('Cloudflare R2')
      expect(info[:description]).to include('egress')
    end

    it 'returns nil for unknown providers' do
      expect(described_class.provider_info('unknown')).to be_nil
    end
  end

  describe '.providers_with_info' do
    it 'returns all providers with metadata' do
      providers = described_class.providers_with_info

      expect(providers.length).to eq(11)
      expect(providers.first).to have_key(:type)
      expect(providers.first).to have_key(:name)
      expect(providers.first).to have_key(:description)
      expect(providers.first).to have_key(:s3_compatible)
      expect(providers.first).to have_key(:network_filesystem)
    end

    it 'marks S3-compatible providers correctly' do
      providers = described_class.providers_with_info
      r2 = providers.find { |p| p[:type] == 'cloudflare_r2' }

      expect(r2[:s3_compatible]).to be true
      expect(r2[:network_filesystem]).to be false
    end

    it 'marks network filesystem providers correctly' do
      providers = described_class.providers_with_info
      nfs = providers.find { |p| p[:type] == 'nfs' }
      smb = providers.find { |p| p[:type] == 'smb' }

      expect(nfs[:network_filesystem]).to be true
      expect(nfs[:s3_compatible]).to be false
      expect(smb[:network_filesystem]).to be true
      expect(smb[:s3_compatible]).to be false
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

    it 'returns capabilities for GCS storage' do
      capabilities = described_class.provider_capabilities('gcs')

      expect(capabilities['multipart_upload']).to be true
      expect(capabilities['signed_urls']).to be true
      expect(capabilities['object_retention']).to be true
    end

    it 'returns capabilities for Azure storage' do
      capabilities = described_class.provider_capabilities('azure')

      expect(capabilities['multipart_upload']).to be true
      expect(capabilities['signed_urls']).to be true
      expect(capabilities['blob_tiers']).to be true
    end

    it 'returns S3 capabilities for S3-compatible providers' do
      %w[backblaze_b2 digitalocean_spaces cloudflare_r2 minio wasabi].each do |provider|
        capabilities = described_class.provider_capabilities(provider)

        expect(capabilities['multipart_upload']).to be true
        expect(capabilities['signed_urls']).to be true
        expect(capabilities['lifecycle_policies']).to be true
      end
    end

    it 'returns capabilities for NFS storage' do
      capabilities = described_class.provider_capabilities('nfs')

      expect(capabilities['network_mount']).to be true
      expect(capabilities['unix_permissions']).to be true
      expect(capabilities['file_locking']).to be true
      expect(capabilities['streaming']).to be true
      expect(capabilities['multipart_upload']).to be false
      expect(capabilities['signed_urls']).to be false
    end

    it 'returns capabilities for SMB storage' do
      capabilities = described_class.provider_capabilities('smb')

      expect(capabilities['network_mount']).to be true
      expect(capabilities['windows_acls']).to be true
      expect(capabilities['file_locking']).to be true
      expect(capabilities['encryption']).to be true
      expect(capabilities['multipart_upload']).to be false
      expect(capabilities['signed_urls']).to be false
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

    it 'checks GCS dependencies' do
      result = described_class.check_dependencies('gcs')

      expect(result).to have_key(:available)
      expect(result).to have_key(:missing)
    end

    it 'checks Azure dependencies' do
      result = described_class.check_dependencies('azure')

      expect(result).to have_key(:available)
      expect(result).to have_key(:missing)
    end

    it 'checks S3 dependencies for S3-compatible providers' do
      %w[backblaze_b2 digitalocean_spaces cloudflare_r2 minio wasabi].each do |provider|
        result = described_class.check_dependencies(provider)

        expect(result).to have_key(:available)
        expect(result).to have_key(:missing)
      end
    end

    it 'checks NFS dependencies' do
      result = described_class.check_dependencies('nfs')

      expect(result).to have_key(:available)
      expect(result).to have_key(:missing)
    end

    it 'checks SMB dependencies' do
      result = described_class.check_dependencies('smb')

      expect(result).to have_key(:available)
      expect(result).to have_key(:missing)
    end

    it 'returns unavailable for unknown provider' do
      result = described_class.check_dependencies('unknown')

      expect(result[:available]).to be false
      expect(result[:missing]).to include('Unknown provider type')
    end
  end

  describe '.get_provider_class' do
    it 'returns class name for core providers' do
      expect(described_class.get_provider_class('local')).to eq('StorageProviders::LocalStorage')
      expect(described_class.get_provider_class('s3')).to eq('StorageProviders::S3Storage')
      expect(described_class.get_provider_class('gcs')).to eq('StorageProviders::GcsStorage')
      expect(described_class.get_provider_class('azure')).to eq('StorageProviders::AzureStorage')
    end

    it 'returns class name for network filesystem providers' do
      expect(described_class.get_provider_class('nfs')).to eq('StorageProviders::NfsStorage')
      expect(described_class.get_provider_class('smb')).to eq('StorageProviders::SmbStorage')
    end

    it 'returns S3Storage class for S3-compatible providers' do
      %w[backblaze_b2 digitalocean_spaces cloudflare_r2 minio wasabi].each do |provider|
        expect(described_class.get_provider_class(provider)).to eq('StorageProviders::S3Storage')
      end
    end

    it 'raises error for invalid provider' do
      expect {
        described_class.get_provider_class('invalid')
      }.to raise_error(StorageProviderFactory::UnsupportedProviderError)
    end

    it 'raises error for unsupported providers' do
      expect {
        described_class.get_provider_class('dropbox')
      }.to raise_error(StorageProviderFactory::UnsupportedProviderError)

      expect {
        described_class.get_provider_class('ftp')
      }.to raise_error(StorageProviderFactory::UnsupportedProviderError)
    end

    it 'is case insensitive' do
      expect(described_class.get_provider_class('LOCAL')).to eq('StorageProviders::LocalStorage')
      expect(described_class.get_provider_class('S3')).to eq('StorageProviders::S3Storage')
      expect(described_class.get_provider_class('GCS')).to eq('StorageProviders::GcsStorage')
      expect(described_class.get_provider_class('AZURE')).to eq('StorageProviders::AzureStorage')
      expect(described_class.get_provider_class('NFS')).to eq('StorageProviders::NfsStorage')
      expect(described_class.get_provider_class('SMB')).to eq('StorageProviders::SmbStorage')
    end
  end
end
