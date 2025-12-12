# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StorageProviders::LocalStorage, type: :service do
  let(:account) { create(:account) }
  let(:storage_config) do
    create(:file_storage,
      account: account,
      provider_type: 'local',
      configuration: { 'root_path' => Rails.root.join('tmp', 'test_storage', account.id).to_s }
    )
  end
  let(:provider) { described_class.new(storage_config) }
  let(:file_object) { create(:file_object, account: account, file_storage: storage_config) }

  after do
    # Clean up test storage
    FileUtils.rm_rf(storage_config.configuration['root_path']) if File.exist?(storage_config.configuration['root_path'])
  end

  describe '#initialize_storage' do
    it 'creates storage directory' do
      provider.initialize_storage
      expect(Dir.exist?(storage_config.configuration['root_path'])).to be true
    end

    it 'returns true on success' do
      result = provider.initialize_storage
      expect(result).to be true
    end

    it 'creates subdirectories for categories' do
      provider.initialize_storage
      root = storage_config.configuration['root_path']

      expect(Dir.exist?(File.join(root, 'user_upload'))).to be true
      expect(Dir.exist?(File.join(root, 'workflow_output'))).to be true
    end
  end

  describe '#upload_file' do
    let(:file_content) { 'Test file content for upload' }
    let(:temp_file) do
      file = Tempfile.new([ 'test', '.txt' ])
      file.write(file_content)
      file.rewind
      file
    end

    before { provider.initialize_storage }
    after { temp_file.close! }

    it 'uploads file to storage and returns true' do
      result = provider.upload_file(file_object, temp_file)
      expect(result).to be true
    end

    it 'creates file at correct path' do
      provider.upload_file(file_object, temp_file)

      full_path = File.join(storage_config.configuration['root_path'], file_object.storage_key)
      expect(File.exist?(full_path)).to be true
      expect(File.read(full_path)).to eq(file_content)
    end

    it 'creates necessary subdirectories' do
      file_object.update!(storage_key: 'deep/nested/path/file.txt')
      provider.upload_file(file_object, temp_file)

      full_path = File.join(storage_config.configuration['root_path'], file_object.storage_key)
      expect(File.exist?(full_path)).to be true
    end

    it 'updates file checksums' do
      provider.upload_file(file_object, temp_file)
      file_object.reload

      expect(file_object.checksum_md5).to be_present
      expect(file_object.checksum_sha256).to be_present
    end
  end

  describe '#read_file' do
    let(:file_content) { 'Test content for reading' }

    before do
      provider.initialize_storage
      file_path = File.join(storage_config.configuration['root_path'], file_object.storage_key)
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, file_content)
    end

    it 'reads file content' do
      content = provider.read_file(file_object)
      expect(content).to eq(file_content)
    end

    it 'raises error for non-existent file' do
      file_object.update!(storage_key: 'non/existent/file.txt')
      expect { provider.read_file(file_object) }.to raise_error(/not found/)
    end
  end

  describe '#stream_file' do
    let(:file_content) { 'x' * 256 * 1024 } # 256KB - small enough for quick test

    before do
      provider.initialize_storage
      file_path = File.join(storage_config.configuration['root_path'], file_object.storage_key)
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, file_content)
    end

    it 'streams file in chunks' do
      chunks = []
      provider.stream_file(file_object) { |chunk| chunks << chunk }

      expect(chunks.join).to eq(file_content)
      expect(chunks.size).to be >= 1
    end
  end

  describe '#delete_file' do
    before do
      provider.initialize_storage
      file_path = File.join(storage_config.configuration['root_path'], file_object.storage_key)
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, 'content to delete')
    end

    it 'deletes file from storage' do
      file_path = File.join(storage_config.configuration['root_path'], file_object.storage_key)

      provider.delete_file(file_object)
      expect(File.exist?(file_path)).to be false
    end

    it 'returns true on success' do
      result = provider.delete_file(file_object)
      expect(result).to be true
    end

    it 'returns true when file already deleted' do
      file_path = File.join(storage_config.configuration['root_path'], file_object.storage_key)
      File.delete(file_path)

      result = provider.delete_file(file_object)
      expect(result).to be true
    end
  end

  describe '#file_exists?' do
    before { provider.initialize_storage }

    it 'returns true when file exists' do
      file_path = File.join(storage_config.configuration['root_path'], file_object.storage_key)
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, 'test')

      expect(provider.file_exists?(file_object)).to be true
    end

    it 'returns false when file does not exist' do
      expect(provider.file_exists?(file_object)).to be false
    end
  end

  describe '#file_metadata' do
    let(:file_content) { 'Test metadata content' }

    before do
      provider.initialize_storage
      file_path = File.join(storage_config.configuration['root_path'], file_object.storage_key)
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, file_content)
    end

    it 'returns file metadata' do
      metadata = provider.file_metadata(file_object)

      expect(metadata['size']).to eq(file_content.bytesize)
      expect(metadata['modified_at']).to be_present
      expect(metadata['readable']).to be true
    end

    it 'raises error for non-existent file' do
      file_object.update!(storage_key: 'non/existent/file.txt')
      expect { provider.file_metadata(file_object) }.to raise_error(/not found/)
    end
  end

  describe '#copy_file' do
    let(:source_key) { 'source/file.txt' }
    let(:destination_key) { 'destination/file.txt' }

    before do
      provider.initialize_storage
      source_path = File.join(storage_config.configuration['root_path'], source_key)
      FileUtils.mkdir_p(File.dirname(source_path))
      File.write(source_path, 'content to copy')
    end

    it 'copies file to new location' do
      result = provider.copy_file(source_key, destination_key)

      expect(result).to be true
      dest_path = File.join(storage_config.configuration['root_path'], destination_key)
      expect(File.exist?(dest_path)).to be true
      expect(File.read(dest_path)).to eq('content to copy')
    end

    it 'keeps original file intact' do
      provider.copy_file(source_key, destination_key)

      source_path = File.join(storage_config.configuration['root_path'], source_key)
      expect(File.exist?(source_path)).to be true
    end
  end

  describe '#move_file' do
    let(:source_key) { 'source/file.txt' }
    let(:destination_key) { 'destination/file.txt' }

    before do
      provider.initialize_storage
      source_path = File.join(storage_config.configuration['root_path'], source_key)
      FileUtils.mkdir_p(File.dirname(source_path))
      File.write(source_path, 'content to move')
    end

    it 'moves file to new location' do
      result = provider.move_file(source_key, destination_key)

      expect(result).to be true
      dest_path = File.join(storage_config.configuration['root_path'], destination_key)
      expect(File.exist?(dest_path)).to be true
      expect(File.read(dest_path)).to eq('content to move')
    end

    it 'removes original file' do
      provider.move_file(source_key, destination_key)

      source_path = File.join(storage_config.configuration['root_path'], source_key)
      expect(File.exist?(source_path)).to be false
    end
  end

  describe '#test_connection' do
    it 'returns success hash when storage is accessible' do
      provider.initialize_storage
      result = provider.test_connection

      expect(result[:success]).to be true
      expect(result[:writable]).to be true
    end

    it 'returns failure hash when path does not exist' do
      # Use a path that doesn't exist but can't be created (use tmp subdirectory and delete it)
      test_path = Rails.root.join('tmp', 'nonexistent_test_storage_path')
      FileUtils.rm_rf(test_path) if test_path.exist?

      storage_config.configuration['root_path'] = test_path.to_s
      # Stub FileUtils.mkdir_p to not actually create
      allow(FileUtils).to receive(:mkdir_p).and_return(nil)

      new_provider = described_class.new(storage_config)
      result = new_provider.test_connection

      expect(result[:success]).to be false
    end
  end

  describe '#health_check' do
    before { provider.initialize_storage }

    it 'returns healthy status when accessible' do
      health = provider.health_check

      expect(health[:status]).to be_in([ 'healthy', 'degraded' ])
      expect(health[:details]).to include('root_path')
      expect(health[:details]['writable']).to be true
    end

    it 'returns failed status when path is not accessible' do
      # Stub test_connection to simulate failed state
      allow(provider).to receive(:test_connection).and_return({
        success: false,
        error: 'Directory does not exist: /nonexistent/path'
      })

      health = provider.health_check

      expect(health[:status]).to eq('failed')
      expect(health[:details]['error']).to be_present
    end
  end

  describe '#list_files' do
    before do
      provider.initialize_storage
      root = storage_config.configuration['root_path']

      FileUtils.mkdir_p(File.join(root, 'folder1'))
      File.write(File.join(root, 'folder1', 'file1.txt'), 'content1')
      File.write(File.join(root, 'folder1', 'file2.txt'), 'content2')

      FileUtils.mkdir_p(File.join(root, 'folder2'))
      File.write(File.join(root, 'folder2', 'file3.txt'), 'content3')
    end

    it 'lists all files in storage' do
      files = provider.list_files

      expect(files.size).to eq(3)
      expect(files.map { |f| f['key'] }).to contain_exactly(
        'folder1/file1.txt',
        'folder1/file2.txt',
        'folder2/file3.txt'
      )
    end

    it 'lists files with specific prefix' do
      files = provider.list_files(prefix: 'folder1')

      expect(files.size).to eq(2)
      expect(files.map { |f| f['key'] }).to all(start_with('folder1/'))
    end
  end

  describe '#file_url' do
    it 'returns file URL path' do
      url = provider.file_url(file_object)
      expect(url).to include(file_object.id)
    end
  end

  describe '#download_url' do
    it 'returns download URL with storage key' do
      url = provider.download_url(file_object, expires_in: 1.hour)
      expect(url).to be_present
      expect(url).to include(file_object.storage_key)
    end
  end

  describe '#signed_url' do
    it 'returns same as download_url for local storage' do
      download = provider.download_url(file_object)
      signed = provider.signed_url(file_object)
      expect(signed).to eq(download)
    end
  end
end
