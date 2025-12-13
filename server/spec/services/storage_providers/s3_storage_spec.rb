# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StorageProviders::S3Storage, type: :service do
  let(:account) { create(:account) }
  let(:storage_config) do
    create(:file_storage, :s3,
      account: account,
      configuration: {
        'bucket' => 'test-bucket',
        'region' => 'us-east-1',
        'access_key_id' => 'AKIAIOSFODNN7EXAMPLE',
        'secret_access_key' => 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
      }
    )
  end
  let(:provider) { described_class.new(storage_config) }
  let(:file_object) { create(:file_object, account: account, file_storage: storage_config) }
  let(:s3_client) { instance_double(Aws::S3::Client) }
  let(:s3_resource) { instance_double(Aws::S3::Resource) }
  let(:bucket) { instance_double(Aws::S3::Bucket) }
  let(:presigner) { instance_double(Aws::S3::Presigner) }

  before do
    # Mock AWS S3 client and resource
    allow(Aws::S3::Client).to receive(:new).and_return(s3_client)
    allow(Aws::S3::Resource).to receive(:new).and_return(s3_resource)
    allow(s3_resource).to receive(:bucket).with('test-bucket').and_return(bucket)
    allow(Aws::S3::Presigner).to receive(:new).and_return(presigner)

    # Mock bucket existence check for initialize
    allow(bucket).to receive(:exists?).and_return(true)
  end

  describe '#initialize_storage' do
    it 'returns true when bucket exists' do
      result = provider.initialize_storage
      expect(result).to be true
    end

    it 'creates bucket if not exists' do
      allow(bucket).to receive(:exists?).and_return(false)
      allow(bucket).to receive(:create).and_return(true)

      result = provider.initialize_storage
      expect(result).to be true
    end

    it 'returns false on S3 error' do
      allow(bucket).to receive(:exists?).and_raise(Aws::S3::Errors::ServiceError.new(nil, 'Error'))

      result = provider.initialize_storage
      expect(result).to be false
    end
  end

  describe '#upload_file' do
    let(:file_content) { 'Test file content for S3 upload' }
    let(:temp_file) do
      file = Tempfile.new([ 'test', '.txt' ])
      file.write(file_content)
      file.rewind
      file
    end

    after { temp_file.close! }

    it 'uploads file to S3 and returns true' do
      expect(s3_client).to receive(:put_object).with(
        hash_including(
          bucket: 'test-bucket',
          key: file_object.storage_key,
          body: anything
        )
      ).and_return(double(etag: '"abc123"'))

      result = provider.upload_file(file_object, temp_file)
      expect(result).to be true
    end

    it 'updates file checksums' do
      allow(s3_client).to receive(:put_object).and_return(double(etag: '"abc123"'))

      provider.upload_file(file_object, temp_file)
      file_object.reload

      expect(file_object.checksum_md5).to be_present
      expect(file_object.checksum_sha256).to be_present
    end
  end

  describe '#read_file' do
    it 'reads file from S3' do
      response = double(body: StringIO.new('S3 file content'))
      allow(s3_client).to receive(:get_object).with(
        bucket: 'test-bucket',
        key: file_object.storage_key
      ).and_return(response)

      content = provider.read_file(file_object)
      expect(content).to eq('S3 file content')
    end

    it 'raises error for non-existent file' do
      allow(s3_client).to receive(:get_object).and_raise(
        Aws::S3::Errors::NoSuchKey.new(nil, 'Not found')
      )

      expect { provider.read_file(file_object) }.to raise_error(/not found/i)
    end
  end

  describe '#stream_file' do
    it 'streams file in chunks' do
      chunks_received = []
      allow(s3_client).to receive(:get_object) do |_params, &block|
        block.call('chunk1')
        block.call('chunk2')
        block.call('chunk3')
      end

      provider.stream_file(file_object) { |chunk| chunks_received << chunk }

      expect(chunks_received).to eq([ 'chunk1', 'chunk2', 'chunk3' ])
    end
  end

  describe '#delete_file' do
    it 'deletes file from S3 and returns true' do
      expect(s3_client).to receive(:delete_object).with(
        bucket: 'test-bucket',
        key: file_object.storage_key
      ).and_return(true)

      result = provider.delete_file(file_object)
      expect(result).to be true
    end

    it 'returns false on S3 error' do
      allow(s3_client).to receive(:delete_object).and_raise(
        Aws::S3::Errors::ServiceError.new(nil, 'Error')
      )

      result = provider.delete_file(file_object)
      expect(result).to be false
    end
  end

  describe '#file_exists?' do
    it 'returns true when file exists' do
      allow(s3_client).to receive(:head_object).with(
        bucket: 'test-bucket',
        key: file_object.storage_key
      ).and_return(true)

      expect(provider.file_exists?(file_object)).to be true
    end

    it 'returns false when file does not exist' do
      allow(s3_client).to receive(:head_object).and_raise(
        Aws::S3::Errors::NotFound.new(nil, 'Not found')
      )

      expect(provider.file_exists?(file_object)).to be false
    end
  end

  describe '#file_metadata' do
    it 'returns file metadata from S3' do
      response = double(
        content_length: 1024,
        last_modified: Time.current,
        content_type: 'text/plain',
        etag: '"abc123"',
        storage_class: 'STANDARD',
        server_side_encryption: 'AES256',
        metadata: { 'custom' => 'value' },
        version_id: nil
      )
      allow(s3_client).to receive(:head_object).with(
        bucket: 'test-bucket',
        key: file_object.storage_key
      ).and_return(response)

      metadata = provider.file_metadata(file_object)

      expect(metadata['size']).to eq(1024)
      expect(metadata['content_type']).to eq('text/plain')
      expect(metadata['etag']).to eq('"abc123"')
    end

    it 'raises error for non-existent file' do
      allow(s3_client).to receive(:head_object).and_raise(
        Aws::S3::Errors::NotFound.new(nil, 'Not found')
      )

      expect { provider.file_metadata(file_object) }.to raise_error(/not found/i)
    end
  end

  describe '#copy_file' do
    let(:source_key) { 'source/file.txt' }
    let(:destination_key) { 'destination/file.txt' }

    it 'copies file within S3 and returns true' do
      expect(s3_client).to receive(:copy_object).with(
        bucket: 'test-bucket',
        copy_source: 'test-bucket/source/file.txt',
        key: destination_key
      ).and_return(true)

      result = provider.copy_file(source_key, destination_key)
      expect(result).to be true
    end

    it 'raises error when source not found' do
      allow(s3_client).to receive(:copy_object).and_raise(
        Aws::S3::Errors::NoSuchKey.new(nil, 'Not found')
      )

      expect { provider.copy_file(source_key, destination_key) }.to raise_error(/not found/i)
    end
  end

  describe '#move_file' do
    let(:source_key) { 'source/file.txt' }
    let(:destination_key) { 'destination/file.txt' }

    it 'copies then deletes source file' do
      expect(s3_client).to receive(:copy_object).and_return(true)
      expect(s3_client).to receive(:delete_object).with(
        bucket: 'test-bucket',
        key: source_key
      ).and_return(true)

      result = provider.move_file(source_key, destination_key)
      expect(result).to be true
    end
  end

  describe '#file_url' do
    it 'returns public URL for file' do
      url = provider.file_url(file_object)

      expect(url).to include('test-bucket')
      expect(url).to include('us-east-1')
      expect(url).to include(file_object.storage_key)
    end

    it 'returns CDN URL when configured' do
      storage_config.configuration['cdn_domain'] = 'cdn.example.com'
      new_provider = described_class.new(storage_config)

      url = new_provider.file_url(file_object)
      expect(url).to include('cdn.example.com')
    end
  end

  describe '#download_url' do
    it 'generates presigned URL' do
      presigned_url = 'https://s3.amazonaws.com/test-bucket/file.txt?signature=abc123'
      allow(presigner).to receive(:presigned_url).with(
        :get_object,
        hash_including(
          bucket: 'test-bucket',
          key: file_object.storage_key,
          expires_in: 3600
        )
      ).and_return(presigned_url)

      url = provider.download_url(file_object, expires_in: 1.hour)
      expect(url).to eq(presigned_url)
    end
  end

  describe '#signed_url' do
    it 'generates signed URL with disposition' do
      presigned_url = 'https://s3.amazonaws.com/test-bucket/file.txt?signature=xyz'
      allow(presigner).to receive(:presigned_url).with(
        :get_object,
        hash_including(
          bucket: 'test-bucket',
          key: file_object.storage_key,
          expires_in: 3600
        )
      ).and_return(presigned_url)

      url = provider.signed_url(file_object, expires_in: 1.hour, disposition: 'inline')
      expect(url).to eq(presigned_url)
    end
  end

  describe '#test_connection' do
    it 'returns success hash when connection works' do
      allow(s3_client).to receive(:list_objects_v2).with(
        bucket: 'test-bucket',
        max_keys: 1
      ).and_return(double(contents: []))
      allow(s3_client).to receive(:config).and_return(double(endpoint: double(to_s: 'https://s3.us-east-1.amazonaws.com')))

      result = provider.test_connection

      expect(result[:success]).to be true
      expect(result[:bucket]).to eq('test-bucket')
    end

    it 'returns failure hash when bucket does not exist' do
      allow(s3_client).to receive(:list_objects_v2).and_raise(
        Aws::S3::Errors::NoSuchBucket.new(nil, 'Not found')
      )

      result = provider.test_connection

      expect(result[:success]).to be false
      expect(result[:error]).to include('does not exist')
    end
  end

  describe '#health_check' do
    it 'returns healthy status when accessible' do
      allow(s3_client).to receive(:list_objects_v2).and_return(
        double(contents: [], is_truncated: false, each: [])
      )
      allow(s3_client).to receive(:get_bucket_encryption).and_return(true)
      allow(s3_client).to receive(:get_bucket_versioning).and_return(double(status: 'Enabled'))
      allow(s3_client).to receive(:config).and_return(double(endpoint: double(to_s: 'https://s3.us-east-1.amazonaws.com')))

      health = provider.health_check

      expect(health[:status]).to eq('healthy')
      expect(health[:details]['accessible']).to be true
    end

    it 'returns failed status on connection failure' do
      allow(s3_client).to receive(:list_objects_v2).and_raise(
        Aws::S3::Errors::ServiceError.new(nil, 'Error')
      )

      health = provider.health_check

      expect(health[:status]).to eq('failed')
      expect(health[:details]['error']).to be_present
    end
  end

  describe '#list_files' do
    it 'lists objects in bucket' do
      objects = [
        double(key: 'file1.txt', size: 1024, last_modified: Time.current, etag: '"a"', storage_class: 'STANDARD'),
        double(key: 'file2.txt', size: 2048, last_modified: Time.current, etag: '"b"', storage_class: 'STANDARD')
      ]

      response = double(contents: objects, each: objects)
      allow(s3_client).to receive(:list_objects_v2).and_return(response)
      allow(response).to receive(:each).and_yield(response)

      files = provider.list_files

      expect(files.size).to eq(2)
      expect(files.first['key']).to eq('file1.txt')
    end

    it 'filters by prefix' do
      objects = [
        double(key: 'folder1/file1.txt', size: 1024, last_modified: Time.current, etag: '"a"', storage_class: 'STANDARD')
      ]

      response = double(contents: objects, each: objects)
      allow(s3_client).to receive(:list_objects_v2).with(
        hash_including(prefix: 'folder1/')
      ).and_return(response)
      allow(response).to receive(:each).and_yield(response)

      files = provider.list_files(prefix: 'folder1/')

      expect(files.size).to eq(1)
      expect(files.first['key']).to start_with('folder1/')
    end
  end

  describe '#batch_delete' do
    it 'deletes multiple files using S3 batch delete' do
      file_objects_to_delete = [ file_object, create(:file_object, account: account, file_storage: storage_config) ]

      response = double(
        deleted: file_objects_to_delete.map { |fo| double(key: fo.storage_key) },
        errors: []
      )
      expect(s3_client).to receive(:delete_objects).and_return(response)

      results = provider.batch_delete(file_objects_to_delete)

      expect(results[:success].size).to eq(2)
      expect(results[:failed]).to be_empty
    end
  end
end
