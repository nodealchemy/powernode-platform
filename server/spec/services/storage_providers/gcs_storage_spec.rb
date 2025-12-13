# frozen_string_literal: true

require 'rails_helper'

# Stub Google Cloud Storage module for testing
module Google
  module Cloud
    class Error < StandardError; end
    module Storage
      class Project; end
      class Bucket; end
      class File; end
    end
  end
end unless defined?(Google::Cloud::Storage)

RSpec.describe StorageProviders::GcsStorage, type: :service do
  let(:account) { create(:account) }
  let(:storage_config) do
    create(:file_storage, :gcs,
      account: account,
      configuration: {
        'bucket' => 'test-bucket',
        'project_id' => 'test-project',
        'location' => 'US',
        'service_account_json' => '{"type": "service_account", "project_id": "test-project"}'
      }
    )
  end
  let(:provider) { described_class.new(storage_config) }
  let(:file_object) { create(:file_object, account: account, file_storage: storage_config) }
  let(:gcs_client) { instance_double(Google::Cloud::Storage::Project) }
  let(:bucket) { instance_double(Google::Cloud::Storage::Bucket) }
  let(:gcs_file) { instance_double(Google::Cloud::Storage::File) }

  before do
    allow(Google::Cloud::Storage).to receive(:new).and_return(gcs_client)
    allow(gcs_client).to receive(:bucket).with('test-bucket').and_return(bucket)
  end

  describe '#initialize' do
    it 'creates a GCS client' do
      expect(Google::Cloud::Storage).to receive(:new).with(
        project_id: 'test-project',
        credentials: anything
      ).and_return(gcs_client)

      described_class.new(storage_config)
    end
  end

  describe '#initialize_storage' do
    it 'returns true when bucket exists' do
      allow(gcs_client).to receive(:bucket).with('test-bucket').and_return(bucket)

      result = provider.initialize_storage
      expect(result).to be true
    end

    it 'creates bucket if not exists' do
      allow(gcs_client).to receive(:bucket).with('test-bucket').and_return(nil)
      allow(gcs_client).to receive(:create_bucket).and_return(bucket)

      result = provider.initialize_storage
      expect(result).to be true
    end

    it 'returns false on GCS error' do
      allow(gcs_client).to receive(:bucket).and_raise(Google::Cloud::Error.new('Error'))

      result = provider.initialize_storage
      expect(result).to be false
    end
  end

  describe '#test_connection' do
    context 'when bucket is accessible' do
      it 'returns success' do
        allow(bucket).to receive(:location).and_return('US')
        allow(bucket).to receive(:storage_class).and_return('STANDARD')

        result = provider.test_connection
        expect(result[:success]).to be true
        expect(result[:bucket]).to eq('test-bucket')
      end
    end

    context 'when bucket does not exist' do
      it 'returns failure' do
        allow(gcs_client).to receive(:bucket).with('test-bucket').and_return(nil)

        result = provider.test_connection
        expect(result[:success]).to be false
        expect(result[:error]).to include('does not exist')
      end
    end
  end

  describe '#upload_file' do
    let(:file_content) { 'Test file content for GCS upload' }
    let(:temp_file) do
      file = Tempfile.new(['test', '.txt'])
      file.write(file_content)
      file.rewind
      file
    end

    after { temp_file.close! }

    it 'uploads file to GCS and returns true' do
      allow(bucket).to receive(:create_file).and_return(gcs_file)

      result = provider.upload_file(file_object, temp_file)
      expect(result).to be true
    end

    it 'raises error on GCS failure' do
      allow(bucket).to receive(:create_file).and_raise(Google::Cloud::Error.new('Upload failed'))

      expect {
        provider.upload_file(file_object, temp_file)
      }.to raise_error(Google::Cloud::Error)
    end
  end

  describe '#read_file' do
    it 'returns file content' do
      allow(bucket).to receive(:file).with(file_object.storage_key).and_return(gcs_file)
      allow(gcs_file).to receive(:download).and_return(StringIO.new('file content'))

      result = provider.read_file(file_object)
      expect(result).to eq('file content')
    end

    it 'raises error when file not found' do
      allow(bucket).to receive(:file).with(file_object.storage_key).and_return(nil)

      expect {
        provider.read_file(file_object)
      }.to raise_error(/File not found/)
    end
  end

  describe '#delete_file' do
    it 'deletes file and returns true' do
      allow(bucket).to receive(:file).with(file_object.storage_key).and_return(gcs_file)
      allow(gcs_file).to receive(:delete).and_return(true)

      result = provider.delete_file(file_object)
      expect(result).to be true
    end

    it 'returns true when file does not exist' do
      allow(bucket).to receive(:file).with(file_object.storage_key).and_return(nil)

      result = provider.delete_file(file_object)
      expect(result).to be true
    end
  end

  describe '#file_exists?' do
    it 'returns true when file exists' do
      allow(bucket).to receive(:file).with(file_object.storage_key).and_return(gcs_file)

      expect(provider.file_exists?(file_object)).to be true
    end

    it 'returns false when file does not exist' do
      allow(bucket).to receive(:file).with(file_object.storage_key).and_return(nil)

      expect(provider.file_exists?(file_object)).to be false
    end
  end

  describe '#download_url' do
    it 'generates signed URL' do
      allow(bucket).to receive(:file).with(file_object.storage_key).and_return(gcs_file)
      allow(gcs_file).to receive(:signed_url).with(any_args).and_return('https://storage.googleapis.com/signed-url')

      result = provider.download_url(file_object)
      expect(result).to include('storage.googleapis.com')
    end
  end

  describe '#list_files' do
    let(:file_list) { [gcs_file] }

    it 'returns list of files' do
      allow(bucket).to receive(:files).and_return(file_list)
      allow(gcs_file).to receive(:name).and_return('test/file.txt')
      allow(gcs_file).to receive(:size).and_return(1024)
      allow(gcs_file).to receive(:updated_at).and_return(Time.current)
      allow(gcs_file).to receive(:content_type).and_return('text/plain')
      allow(gcs_file).to receive(:storage_class).and_return('STANDARD')

      result = provider.list_files
      expect(result).to be_an(Array)
      expect(result.first['key']).to eq('test/file.txt')
    end
  end

  describe '#copy_file' do
    it 'copies file and returns true' do
      allow(bucket).to receive(:file).with('source/file.txt').and_return(gcs_file)
      allow(gcs_file).to receive(:copy).and_return(true)

      result = provider.copy_file('source/file.txt', 'dest/file.txt')
      expect(result).to be true
    end
  end

  describe '#health_check' do
    context 'when healthy' do
      it 'returns healthy status' do
        allow(bucket).to receive(:location).and_return('US')
        allow(bucket).to receive(:storage_class).and_return('STANDARD')

        result = provider.health_check
        expect(result[:status]).to eq('healthy')
      end
    end
  end
end
