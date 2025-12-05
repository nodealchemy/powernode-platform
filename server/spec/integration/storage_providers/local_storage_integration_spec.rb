# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'StorageProviders::LocalStorage Integration', type: :integration do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:test_root_path) { Rails.root.join('tmp', 'integration_storage_test', account.id) }

  let!(:storage) do
    create(:file_storage,
      account: account,
      name: 'Integration Test Storage',
      provider_type: 'local',
      configuration: {
        'root_path' => test_root_path.to_s,
        'url_base' => 'http://localhost:3000/files'
      },
      is_default: true,
      status: 'active',
      quota_bytes: 50.megabytes
    )
  end

  let(:provider) { StorageProviderFactory.get_provider(storage) }

  before do
    FileUtils.mkdir_p(test_root_path)
  end

  after do
    FileUtils.rm_rf(test_root_path)
  end

  describe 'Storage Provider Factory' do
    it 'creates correct provider instance' do
      expect(provider).to be_a(StorageProviders::LocalStorage)
      expect(provider.storage_config).to eq(storage)
    end

    it 'raises error for unknown provider type' do
      invalid_storage = FileStorage.new(
        account: account,
        name: 'Invalid',
        provider_type: 'unknown',
        configuration: {}
      )

      expect {
        StorageProviderFactory.get_provider(invalid_storage)
      }.to raise_error(ArgumentError, /Unsupported storage provider/)
    end
  end

  describe 'Connection and Health Checks' do
    it 'initializes storage successfully' do
      expect { provider.initialize_storage }.not_to raise_error
      expect(Dir.exist?(test_root_path)).to be true
    end

    it 'tests connection successfully' do
      result = provider.test_connection
      expect(result).to be true
    end

    it 'performs health check' do
      health = provider.health_check

      expect(health[:healthy]).to be true
      expect(health[:writable]).to be true
      expect(health[:readable]).to be true
      expect(health[:available_space_bytes]).to be > 0
    end

    it 'detects unhealthy storage when directory missing' do
      FileUtils.rm_rf(test_root_path)

      health = provider.health_check

      expect(health[:healthy]).to be false
      expect(health[:error]).to be_present
    end
  end

  describe 'File Upload Operations' do
    let(:test_content) { 'This is test file content for upload testing.' }
    let(:file_object) do
      FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'test_upload.txt',
        storage_key: "uploads/#{SecureRandom.uuid}/test_upload.txt",
        content_type: 'text/plain',
        file_size: test_content.bytesize,
        file_type: 'document',
        category: 'user_upload'
      )
    end

    it 'uploads file from StringIO' do
      file_data = StringIO.new(test_content)

      result = provider.upload_file(file_object, file_data)

      expect(result).to be true
      expect(provider.file_exists?(file_object)).to be true

      # Verify file content
      uploaded_content = provider.read_file(file_object)
      expect(uploaded_content).to eq(test_content)
    end

    it 'uploads file from File object' do
      temp_file = Tempfile.new('test_upload')
      temp_file.write(test_content)
      temp_file.rewind

      result = provider.upload_file(file_object, temp_file)

      expect(result).to be true
      expect(provider.file_exists?(file_object)).to be true

      temp_file.close
      temp_file.unlink
    end

    it 'creates nested directories automatically' do
      nested_file = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'nested.txt',
        storage_key: 'deep/nested/path/structure/nested.txt',
        content_type: 'text/plain',
        file_size: test_content.bytesize,
        file_type: 'document',
        category: 'user_upload'
      )

      result = provider.upload_file(nested_file, StringIO.new(test_content))

      expect(result).to be true
      expect(provider.file_exists?(nested_file)).to be true
    end

    it 'handles file overwrites' do
      # Upload initial content
      provider.upload_file(file_object, StringIO.new(test_content))

      # Upload new content
      new_content = 'Updated content'
      provider.upload_file(file_object, StringIO.new(new_content))

      uploaded_content = provider.read_file(file_object)
      expect(uploaded_content).to eq(new_content)
    end

    it 'validates file size limits' do
      large_content = 'a' * 6.gigabytes
      large_file = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'large.txt',
        storage_key: 'large/file.txt',
        content_type: 'text/plain',
        file_size: large_content.bytesize,
        file_type: 'document',
        category: 'user_upload'
      )

      expect {
        provider.upload_file(large_file, StringIO.new(large_content))
      }.to raise_error(ArgumentError, /exceeds maximum/)
    end
  end

  describe 'File Read Operations' do
    let(:test_content) { 'Content to read' }
    let(:file_object) do
      obj = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'read_test.txt',
        storage_key: "reads/#{SecureRandom.uuid}/read_test.txt",
        content_type: 'text/plain',
        file_size: test_content.bytesize,
        file_type: 'document',
        category: 'user_upload'
      )

      provider.upload_file(obj, StringIO.new(test_content))
      obj
    end

    it 'reads file content' do
      content = provider.read_file(file_object)

      expect(content).to eq(test_content)
    end

    it 'streams file content in chunks' do
      chunks = []
      provider.stream_file(file_object) do |chunk|
        chunks << chunk
      end

      expect(chunks.join).to eq(test_content)
    end

    it 'raises error when reading non-existent file' do
      non_existent = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'missing.txt',
        storage_key: 'missing/file.txt',
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload'
      )

      expect {
        provider.read_file(non_existent)
      }.to raise_error(Errno::ENOENT)
    end

    it 'gets file metadata' do
      metadata = provider.file_metadata(file_object)

      expect(metadata[:size]).to eq(test_content.bytesize)
      expect(metadata[:modified_at]).to be_present
      expect(metadata[:content_type]).to be_present
    end
  end

  describe 'File URL Generation' do
    let(:file_object) do
      FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'url_test.txt',
        storage_key: 'urls/test.txt',
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload'
      )
    end

    it 'generates file URL' do
      url = provider.file_url(file_object)

      expect(url).to include('http://localhost:3000/files')
      expect(url).to include(file_object.storage_key)
    end

    it 'generates download URL' do
      download_url = provider.download_url(file_object, expires_in: 1.hour)

      expect(download_url).to be_present
      expect(download_url).to include(file_object.storage_key)
    end

    it 'generates signed URL with expiration' do
      signed_url = provider.signed_url(file_object, expires_in: 30.minutes, disposition: 'attachment')

      expect(signed_url).to be_present
      expect(signed_url).to include(file_object.storage_key)
    end
  end

  describe 'File Copy and Move Operations' do
    let(:test_content) { 'File to copy or move' }
    let(:source_key) { "source/#{SecureRandom.uuid}/original.txt" }
    let(:destination_key) { "destination/#{SecureRandom.uuid}/copied.txt" }

    let(:source_file) do
      obj = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'original.txt',
        storage_key: source_key,
        content_type: 'text/plain',
        file_size: test_content.bytesize,
        file_type: 'document',
        category: 'user_upload'
      )

      provider.upload_file(obj, StringIO.new(test_content))
      obj
    end

    it 'copies file to new location' do
      result = provider.copy_file(source_key, destination_key)

      expect(result).to be true

      # Verify both files exist
      expect(File.exist?(test_root_path.join(source_key))).to be true
      expect(File.exist?(test_root_path.join(destination_key))).to be true

      # Verify content is identical
      source_content = File.read(test_root_path.join(source_key))
      dest_content = File.read(test_root_path.join(destination_key))
      expect(dest_content).to eq(source_content)
    end

    it 'moves file to new location' do
      result = provider.move_file(source_key, destination_key)

      expect(result).to be true

      # Verify source is gone, destination exists
      expect(File.exist?(test_root_path.join(source_key))).to be false
      expect(File.exist?(test_root_path.join(destination_key))).to be true

      # Verify content is preserved
      dest_content = File.read(test_root_path.join(destination_key))
      expect(dest_content).to eq(test_content)
    end
  end

  describe 'File Deletion Operations' do
    let(:test_content) { 'File to delete' }
    let(:file_object) do
      obj = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'delete_test.txt',
        storage_key: "deletes/#{SecureRandom.uuid}/delete_test.txt",
        content_type: 'text/plain',
        file_size: test_content.bytesize,
        file_type: 'document',
        category: 'user_upload'
      )

      provider.upload_file(obj, StringIO.new(test_content))
      obj
    end

    it 'deletes file successfully' do
      expect(provider.file_exists?(file_object)).to be true

      result = provider.delete_file(file_object)

      expect(result).to be true
      expect(provider.file_exists?(file_object)).to be false
    end

    it 'handles deletion of non-existent file gracefully' do
      non_existent = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'never_uploaded.txt',
        storage_key: 'missing/never_uploaded.txt',
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload'
      )

      # Should not raise error
      result = provider.delete_file(non_existent)
      expect(result).to be true
    end
  end

  describe 'Batch Operations' do
    let(:test_content) { 'Batch test content' }
    let(:file_objects) do
      5.times.map do |i|
        obj = FileObject.create!(
          account: account,
          file_storage: storage,
          uploaded_by: user,
          filename: "batch_#{i}.txt",
          storage_key: "batch/#{SecureRandom.uuid}/file_#{i}.txt",
          content_type: 'text/plain',
          file_size: test_content.bytesize,
          file_type: 'document',
          category: 'user_upload'
        )

        provider.upload_file(obj, StringIO.new(test_content))
        obj
      end
    end

    it 'batch deletes multiple files' do
      results = provider.batch_delete(file_objects)

      expect(results[:success].length).to eq(5)
      expect(results[:failed].length).to eq(0)

      file_objects.each do |file_obj|
        expect(provider.file_exists?(file_obj)).to be false
      end
    end

    it 'handles partial batch delete failures' do
      # Delete one file manually to cause failure
      File.delete(test_root_path.join(file_objects.first.storage_key))

      results = provider.batch_delete(file_objects)

      # All should succeed (delete_file handles missing files gracefully)
      expect(results[:success].length).to eq(5)
      expect(results[:failed].length).to eq(0)
    end
  end

  describe 'File Listing Operations' do
    before do
      # Create test files in different directories
      ['docs/file1.txt', 'docs/file2.txt', 'images/photo.jpg', 'data/export.csv'].each do |key|
        obj = FileObject.create!(
          account: account,
          file_storage: storage,
          uploaded_by: user,
          filename: File.basename(key),
          storage_key: key,
          content_type: 'text/plain',
          file_size: 100,
          file_type: 'document',
          category: 'user_upload'
        )

        provider.upload_file(obj, StringIO.new('test content'))
      end
    end

    it 'lists all files' do
      files = provider.list_files

      expect(files.length).to be >= 4
    end

    it 'lists files with prefix filter' do
      files = provider.list_files(prefix: 'docs/')

      expect(files.length).to eq(2)
      expect(files.all? { |f| f[:key].start_with?('docs/') }).to be true
    end
  end

  describe 'Checksum Calculations' do
    let(:test_content) { 'Content for checksum' }

    it 'calculates MD5 checksum' do
      checksum = provider.calculate_checksum(test_content, algorithm: :md5)

      expected = Digest::MD5.hexdigest(test_content)
      expect(checksum).to eq(expected)
    end

    it 'calculates SHA256 checksum' do
      checksum = provider.calculate_checksum(test_content, algorithm: :sha256)

      expected = Digest::SHA256.hexdigest(test_content)
      expect(checksum).to eq(expected)
    end

    it 'calculates checksum from IO object' do
      io = StringIO.new(test_content)
      checksum = provider.calculate_checksum(io, algorithm: :sha256)

      expected = Digest::SHA256.hexdigest(test_content)
      expect(checksum).to eq(expected)

      # Verify IO is rewound
      expect(io.pos).to eq(0)
    end
  end

  describe 'Storage Statistics' do
    it 'returns storage statistics' do
      stats = provider.storage_statistics

      expect(stats[:provider_type]).to eq('local')
      expect(stats[:files_count]).to be >= 0
      expect(stats[:total_size_bytes]).to be >= 0
      expect(stats[:quota_bytes]).to eq(50.megabytes)
      expect(stats[:available_space_bytes]).to be >= 0
    end
  end

  describe 'Concurrent Operations' do
    it 'handles concurrent file uploads' do
      # Create all file objects in main thread before threading
      file_objects = 10.times.map do |i|
        FileObject.create!(
          account: account,
          file_storage: storage,
          uploaded_by: user,
          filename: "concurrent_#{i}.txt",
          storage_key: "concurrent/#{SecureRandom.uuid}/file_#{i}.txt",
          content_type: 'text/plain',
          file_size: 100,
          file_type: 'document',
          category: 'user_upload'
        )
      end

      # Only perform I/O operations in threads
      threads = file_objects.each_with_index.map do |file_obj, i|
        Thread.new do
          provider.upload_file(file_obj, StringIO.new("Content #{i}"))
        end
      end

      results = threads.map(&:value)
      expect(results.all?).to be true
    end
  end
end
