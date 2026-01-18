# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StorageProviders::AzureStorage, type: :service do
  let(:account) { create(:account) }
  let(:storage_config) do
    create(:file_storage, :azure,
      account: account,
      configuration: {
        'container' => 'test-container',
        'storage_account_name' => 'teststorageaccount',
        'account_name' => 'teststorageaccount',
        'account_key' => Base64.strict_encode64('testkey123456789012345678901234567890')
      }
    )
  end
  let(:provider) { described_class.new(storage_config) }
  let(:file_object) { create(:file_object, account: account, storage: storage_config) }

  # Helper to stub Faraday responses
  def stub_azure_request(method:, path_pattern:, status:, body: '', headers: {})
    stub_request(method, /#{Regexp.escape('teststorageaccount.blob.core.windows.net')}#{path_pattern}/)
      .to_return(status: status, body: body, headers: headers)
  end

  describe '#initialize' do
    it 'creates provider with Faraday connection' do
      expect(provider.container_name).to eq('test-container')
    end
  end

  describe '#initialize_storage' do
    it 'returns true when container exists' do
      stub_azure_request(
        method: :get,
        path_pattern: '/test-container\?restype=container',
        status: 200
      )

      result = provider.initialize_storage
      expect(result).to be true
    end

    it 'creates container if not exists' do
      stub_azure_request(
        method: :get,
        path_pattern: '/test-container\?restype=container',
        status: 404,
        body: '<Error><Code>ContainerNotFound</Code></Error>'
      )
      stub_azure_request(
        method: :put,
        path_pattern: '/test-container\?restype=container',
        status: 201
      )

      result = provider.initialize_storage
      expect(result).to be true
    end

    it 'returns false on Azure error' do
      stub_azure_request(
        method: :get,
        path_pattern: '/test-container\?restype=container',
        status: 500,
        body: '<Error><Code>InternalError</Code></Error>'
      )

      result = provider.initialize_storage
      expect(result).to be false
    end
  end

  describe '#test_connection' do
    context 'when container is accessible' do
      it 'returns success' do
        stub_azure_request(
          method: :get,
          path_pattern: '/test-container\?restype=container',
          status: 200
        )

        result = provider.test_connection
        expect(result[:success]).to be true
        expect(result[:container]).to eq('test-container')
      end
    end

    context 'when container does not exist' do
      it 'returns failure' do
        stub_azure_request(
          method: :get,
          path_pattern: '/test-container\?restype=container',
          status: 404,
          body: '<Error><Code>ContainerNotFound</Code></Error>'
        )

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
      stub_azure_request(
        method: :put,
        path_pattern: "/test-container/#{file_object.storage_key}",
        status: 201
      )

      result = provider.upload_file(file_object, temp_file)
      expect(result).to be true
    end

    it 'raises error on Azure failure' do
      stub_azure_request(
        method: :put,
        path_pattern: "/test-container/#{file_object.storage_key}",
        status: 500,
        body: '<Error><Code>InternalError</Code><Message>Upload failed</Message></Error>'
      )

      expect {
        provider.upload_file(file_object, temp_file)
      }.to raise_error(StorageProviders::AzureStorage::AzureError)
    end
  end

  describe '#read_file' do
    it 'returns file content' do
      stub_azure_request(
        method: :get,
        path_pattern: "/test-container/#{file_object.storage_key}",
        status: 200,
        body: 'file content'
      )

      result = provider.read_file(file_object)
      expect(result).to eq('file content')
    end

    it 'raises error when file not found' do
      stub_azure_request(
        method: :get,
        path_pattern: "/test-container/#{file_object.storage_key}",
        status: 404,
        body: '<Error><Code>BlobNotFound</Code></Error>'
      )

      expect {
        provider.read_file(file_object)
      }.to raise_error(/File not found/)
    end
  end

  describe '#delete_file' do
    it 'deletes file and returns true' do
      stub_azure_request(
        method: :delete,
        path_pattern: "/test-container/#{file_object.storage_key}",
        status: 202
      )

      result = provider.delete_file(file_object)
      expect(result).to be true
    end

    it 'returns true when file does not exist' do
      stub_azure_request(
        method: :delete,
        path_pattern: "/test-container/#{file_object.storage_key}",
        status: 404,
        body: '<Error><Code>BlobNotFound</Code></Error>'
      )

      result = provider.delete_file(file_object)
      expect(result).to be true
    end
  end

  describe '#file_exists?' do
    it 'returns true when file exists' do
      stub_azure_request(
        method: :head,
        path_pattern: "/test-container/#{file_object.storage_key}",
        status: 200,
        headers: { 'content-length' => '1024' }
      )

      expect(provider.file_exists?(file_object)).to be true
    end

    it 'returns false when file does not exist' do
      stub_azure_request(
        method: :head,
        path_pattern: "/test-container/#{file_object.storage_key}",
        status: 404
      )

      expect(provider.file_exists?(file_object)).to be false
    end
  end

  describe '#list_files' do
    let(:blob_list_xml) do
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <EnumerationResults>
          <Blobs>
            <Blob>
              <Name>test/file.txt</Name>
              <Properties>
                <Content-Length>1024</Content-Length>
                <Content-Type>text/plain</Content-Type>
                <Last-Modified>Wed, 01 Jan 2025 00:00:00 GMT</Last-Modified>
                <BlobType>BlockBlob</BlobType>
              </Properties>
            </Blob>
          </Blobs>
        </EnumerationResults>
      XML
    end

    it 'returns list of files' do
      stub_azure_request(
        method: :get,
        path_pattern: '/test-container\?',
        status: 200,
        body: blob_list_xml
      )

      result = provider.list_files
      expect(result).to be_an(Array)
      expect(result.first['key']).to eq('test/file.txt')
    end
  end

  describe '#copy_file' do
    it 'copies file and returns true' do
      stub_azure_request(
        method: :put,
        path_pattern: '/test-container/dest/file.txt',
        status: 202
      )

      result = provider.copy_file('source/file.txt', 'dest/file.txt')
      expect(result).to be true
    end
  end

  describe '#health_check' do
    context 'when healthy' do
      it 'returns healthy status' do
        stub_azure_request(
          method: :get,
          path_pattern: '/test-container\?restype=container',
          status: 200
        )

        result = provider.health_check
        expect(result[:status]).to eq('healthy')
      end
    end
  end

  describe '#download_url' do
    it 'generates SAS URL' do
      result = provider.download_url(file_object)
      expect(result).to include('blob.core.windows.net')
      expect(result).to include('sig=')
      expect(result).to include('sv=')
    end
  end

  describe '#file_url' do
    it 'returns standard Azure URL' do
      expect(provider.file_url(file_object)).to include('teststorageaccount.blob.core.windows.net')
    end

    it 'uses CDN domain when configured' do
      storage_config.configuration['cdn_domain'] = 'cdn.example.com'
      expect(provider.file_url(file_object)).to include('cdn.example.com')
    end
  end

  describe '#file_metadata' do
    it 'returns file metadata from blob properties' do
      stub_azure_request(
        method: :head,
        path_pattern: "/test-container/#{file_object.storage_key}",
        status: 200,
        headers: {
          'content-length' => '1024',
          'content-type' => 'text/plain',
          'etag' => '"abc123"',
          'last-modified' => 'Wed, 01 Jan 2025 00:00:00 GMT',
          'x-ms-blob-type' => 'BlockBlob',
          'x-ms-meta-custom' => 'value'
        }
      )

      result = provider.file_metadata(file_object)
      expect(result['size']).to eq(1024)
      expect(result['content_type']).to eq('text/plain')
      expect(result['blob_type']).to eq('BlockBlob')
      expect(result['metadata']['custom']).to eq('value')
    end
  end

  describe '#batch_delete' do
    let(:file_objects) { create_list(:file_object, 3, account: account, storage: storage_config) }

    it 'deletes multiple files' do
      file_objects.each do |fo|
        stub_azure_request(
          method: :delete,
          path_pattern: "/test-container/#{fo.storage_key}",
          status: 202
        )
      end

      result = provider.batch_delete(file_objects)
      expect(result[:success].length).to eq(3)
      expect(result[:failed]).to be_empty
    end
  end
end
