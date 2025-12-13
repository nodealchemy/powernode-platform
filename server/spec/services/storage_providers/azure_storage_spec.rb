# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StorageProviders::AzureStorage, type: :service do
  # Helper to create mock HTTP response for Azure errors
  def mock_http_response(status:, body: '')
    response = double('HTTP Response')
    allow(response).to receive(:status).and_return(status)
    allow(response).to receive(:status_code).and_return(status)
    allow(response).to receive(:body).and_return(body)
    allow(response).to receive(:uri).and_return(URI.parse('https://test.blob.core.windows.net/'))
    allow(response).to receive(:headers).and_return({})
    allow(response).to receive(:reason_phrase).and_return('Error')
    response
  end

  let(:account) { create(:account) }
  let(:storage_config) do
    create(:file_storage, :azure,
      account: account,
      configuration: {
        'container' => 'test-container',
        'storage_account_name' => 'teststorageaccount',
        'account_name' => 'teststorageaccount',
        'account_key' => 'dGVzdGtleQ==' # base64 encoded 'testkey'
      }
    )
  end
  let(:provider) { described_class.new(storage_config) }
  let(:file_object) { create(:file_object, account: account, file_storage: storage_config) }
  let(:blob_client) { instance_double(Azure::Storage::Blob::BlobService) }

  before do
    allow(Azure::Storage::Blob::BlobService).to receive(:create).and_return(blob_client)
  end

  describe '#initialize' do
    it 'creates an Azure blob client' do
      expect(Azure::Storage::Blob::BlobService).to receive(:create).and_return(blob_client)

      described_class.new(storage_config)
    end
  end

  describe '#initialize_storage' do
    it 'returns true when container exists' do
      allow(blob_client).to receive(:get_container_properties).and_return(double)

      result = provider.initialize_storage
      expect(result).to be true
    end

    it 'creates container if not exists' do
      http_error = Azure::Core::Http::HTTPError.new(mock_http_response(status: 404))
      allow(blob_client).to receive(:get_container_properties).and_raise(http_error)
      allow(blob_client).to receive(:create_container).and_return(true)

      result = provider.initialize_storage
      expect(result).to be true
    end

    it 'returns false on Azure error' do
      http_error = Azure::Core::Http::HTTPError.new(mock_http_response(status: 500, body: 'Error'))
      allow(blob_client).to receive(:get_container_properties).and_raise(http_error)

      result = provider.initialize_storage
      expect(result).to be false
    end
  end

  describe '#test_connection' do
    context 'when container is accessible' do
      it 'returns success' do
        allow(blob_client).to receive(:get_container_properties).and_return(double)

        result = provider.test_connection
        expect(result[:success]).to be true
        expect(result[:container]).to eq('test-container')
      end
    end

    context 'when container does not exist' do
      it 'returns failure' do
        http_error = Azure::Core::Http::HTTPError.new(mock_http_response(status: 404))
        allow(blob_client).to receive(:get_container_properties).and_raise(http_error)

        result = provider.test_connection
        expect(result[:success]).to be false
        expect(result[:error]).to include('does not exist')
      end
    end
  end

  describe '#upload_file' do
    let(:file_content) { 'Test file content for Azure upload' }
    let(:temp_file) do
      file = Tempfile.new(['test', '.txt'])
      file.write(file_content)
      file.rewind
      file
    end

    after { temp_file.close! }

    it 'uploads file to Azure and returns true' do
      allow(blob_client).to receive(:create_block_blob).and_return(double)

      result = provider.upload_file(file_object, temp_file)
      expect(result).to be true
    end

    it 'raises error on Azure failure' do
      http_error = Azure::Core::Http::HTTPError.new(mock_http_response(status: 500, body: 'Upload failed'))
      allow(blob_client).to receive(:create_block_blob).and_raise(http_error)

      expect {
        provider.upload_file(file_object, temp_file)
      }.to raise_error(Azure::Core::Http::HTTPError)
    end
  end

  describe '#read_file' do
    it 'returns file content' do
      allow(blob_client).to receive(:get_blob).and_return([double, 'file content'])

      result = provider.read_file(file_object)
      expect(result).to eq('file content')
    end

    it 'raises error when file not found' do
      http_error = Azure::Core::Http::HTTPError.new(mock_http_response(status: 404))
      allow(blob_client).to receive(:get_blob).and_raise(http_error)

      expect {
        provider.read_file(file_object)
      }.to raise_error(/File not found/)
    end
  end

  describe '#delete_file' do
    it 'deletes file and returns true' do
      allow(blob_client).to receive(:delete_blob).and_return(true)

      result = provider.delete_file(file_object)
      expect(result).to be true
    end

    it 'returns true when file does not exist' do
      http_error = Azure::Core::Http::HTTPError.new(mock_http_response(status: 404))
      allow(blob_client).to receive(:delete_blob).and_raise(http_error)

      result = provider.delete_file(file_object)
      expect(result).to be true
    end
  end

  describe '#file_exists?' do
    it 'returns true when file exists' do
      allow(blob_client).to receive(:get_blob_properties).and_return(double)

      expect(provider.file_exists?(file_object)).to be true
    end

    it 'returns false when file does not exist' do
      http_error = Azure::Core::Http::HTTPError.new(mock_http_response(status: 404))
      allow(blob_client).to receive(:get_blob_properties).and_raise(http_error)

      expect(provider.file_exists?(file_object)).to be false
    end
  end

  describe '#list_files' do
    let(:blob) { double(name: 'test/file.txt', properties: { content_length: 1024, last_modified: Time.current, content_type: 'text/plain', blob_type: 'BlockBlob' }) }

    it 'returns list of files' do
      allow(blob_client).to receive(:list_blobs).and_return([blob])

      result = provider.list_files
      expect(result).to be_an(Array)
      expect(result.first['key']).to eq('test/file.txt')
    end
  end

  describe '#copy_file' do
    it 'copies file and returns true' do
      allow(blob_client).to receive(:copy_blob_from_uri).and_return(true)

      result = provider.copy_file('source/file.txt', 'dest/file.txt')
      expect(result).to be true
    end
  end

  describe '#health_check' do
    context 'when healthy' do
      it 'returns healthy status' do
        allow(blob_client).to receive(:get_container_properties).and_return(double)

        result = provider.health_check
        expect(result[:status]).to eq('healthy')
      end
    end
  end

  describe '#download_url' do
    it 'generates SAS URL' do
      allow(provider).to receive(:generate_sas_url).and_return('https://teststorageaccount.blob.core.windows.net/test-container/file.txt?sv=...')

      result = provider.download_url(file_object)
      expect(result).to include('blob.core.windows.net')
    end
  end
end
