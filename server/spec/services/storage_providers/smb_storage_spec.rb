# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StorageProviders::SmbStorage, type: :service do
  let(:account) { create(:account) }
  let(:mount_path) { Rails.root.join('tmp', 'test_smb_storage').to_s }
  let(:storage_config) do
    create(:file_storage, :smb,
      account: account,
      configuration: {
        'mount_path' => mount_path,
        'server_address' => '192.168.1.200',
        'share_name' => 'storage',
        'username' => 'testuser',
        'domain' => 'WORKGROUP'
      }
    )
  end
  let(:provider) { described_class.new(storage_config) }
  let(:file_object) { create(:file_object, account: account, storage: storage_config) }

  before do
    FileUtils.mkdir_p(mount_path)
    # Stub the mounted? check to return true for tests
    allow(provider).to receive(:mounted?).and_return(true)
  end

  after do
    FileUtils.rm_rf(mount_path)
  end

  describe '#initialize' do
    it 'sets mount path from config' do
      expect(provider.mount_path).to eq(mount_path)
    end
  end

  describe '#initialize_storage' do
    it 'returns true when mount is accessible' do
      result = provider.initialize_storage
      expect(result).to be true
    end

    it 'creates directory structure' do
      provider.initialize_storage

      expect(File.directory?(File.join(mount_path, 'files'))).to be true
      expect(File.directory?(File.join(mount_path, 'temp'))).to be true
      expect(File.directory?(File.join(mount_path, 'archive'))).to be true
    end

    it 'returns false when mount fails' do
      allow(provider).to receive(:mounted?).and_return(false)
      allow(provider).to receive(:mount_smb_share).and_return(false)

      result = provider.initialize_storage
      expect(result).to be false
    end
  end

  describe '#test_connection' do
    context 'when mount is accessible and writable' do
      it 'returns success' do
        result = provider.test_connection
        expect(result[:success]).to be true
        expect(result[:mount_path]).to eq(mount_path)
        expect(result[:server]).to eq('192.168.1.200')
      end
    end

    context 'when mount path does not exist' do
      it 'returns failure' do
        allow(File).to receive(:directory?).with(mount_path).and_return(false)

        result = provider.test_connection
        expect(result[:success]).to be false
        expect(result[:error]).to include('does not exist')
      end
    end

    context 'when not mounted' do
      it 'returns failure' do
        allow(provider).to receive(:mounted?).and_return(false)

        result = provider.test_connection
        expect(result[:success]).to be false
        expect(result[:error]).to include('not mounted')
      end
    end
  end

  describe '#upload_file' do
    let(:file_content) { 'Test file content for SMB upload' }
    let(:temp_file) do
      file = Tempfile.new([ 'test', '.txt' ])
      file.write(file_content)
      file.rewind
      file
    end

    after { temp_file.close! }

    it 'uploads file and returns true' do
      result = provider.upload_file(file_object, temp_file)
      expect(result).to be true
    end

    it 'creates parent directories' do
      file_object.update(storage_key: 'deep/nested/path/file.txt')

      provider.upload_file(file_object, temp_file)

      expect(File.exist?(File.join(mount_path, 'deep', 'nested', 'path', 'file.txt'))).to be true
    end

    it 'writes correct content' do
      provider.upload_file(file_object, temp_file)

      full_path = File.join(mount_path, file_object.storage_key)
      expect(File.read(full_path)).to eq(file_content)
    end
  end

  describe '#read_file' do
    before do
      full_path = File.join(mount_path, file_object.storage_key)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, 'test content')
    end

    it 'returns file content' do
      result = provider.read_file(file_object)
      expect(result).to eq('test content')
    end

    it 'raises error when file not found' do
      file_object.update(storage_key: 'nonexistent.txt')

      expect {
        provider.read_file(file_object)
      }.to raise_error(/File not found/)
    end
  end

  describe '#delete_file' do
    before do
      full_path = File.join(mount_path, file_object.storage_key)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, 'test content')
    end

    it 'deletes file and returns true' do
      result = provider.delete_file(file_object)
      expect(result).to be true
      expect(File.exist?(File.join(mount_path, file_object.storage_key))).to be false
    end

    it 'returns true when file does not exist' do
      file_object.update(storage_key: 'nonexistent.txt')

      result = provider.delete_file(file_object)
      expect(result).to be true
    end
  end

  describe '#file_exists?' do
    it 'returns true when file exists' do
      full_path = File.join(mount_path, file_object.storage_key)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, 'test')

      expect(provider.file_exists?(file_object)).to be true
    end

    it 'returns false when file does not exist' do
      expect(provider.file_exists?(file_object)).to be false
    end
  end

  describe '#copy_file' do
    before do
      source_path = File.join(mount_path, 'source.txt')
      File.write(source_path, 'source content')
    end

    it 'copies file and returns true' do
      result = provider.copy_file('source.txt', 'dest.txt')
      expect(result).to be true
      expect(File.exist?(File.join(mount_path, 'dest.txt'))).to be true
    end

    it 'raises error when source not found' do
      expect {
        provider.copy_file('nonexistent.txt', 'dest.txt')
      }.to raise_error(/Source file not found/)
    end
  end

  describe '#move_file' do
    before do
      source_path = File.join(mount_path, 'source.txt')
      File.write(source_path, 'source content')
    end

    it 'moves file and returns true' do
      result = provider.move_file('source.txt', 'dest.txt')
      expect(result).to be true
      expect(File.exist?(File.join(mount_path, 'dest.txt'))).to be true
      expect(File.exist?(File.join(mount_path, 'source.txt'))).to be false
    end
  end

  describe '#list_files' do
    before do
      FileUtils.mkdir_p(File.join(mount_path, 'subdir'))
      File.write(File.join(mount_path, 'file1.txt'), 'content1')
      File.write(File.join(mount_path, 'subdir', 'file2.txt'), 'content2')
    end

    it 'returns list of files' do
      result = provider.list_files

      expect(result).to be_an(Array)
      expect(result.map { |f| f['key'] }).to include('file1.txt', 'subdir/file2.txt')
    end

    it 'filters by prefix' do
      result = provider.list_files(prefix: 'subdir')

      expect(result.size).to eq(1)
      expect(result.first['key']).to eq('subdir/file2.txt')
    end
  end

  describe '#health_check' do
    context 'when healthy' do
      it 'returns healthy status' do
        result = provider.health_check
        expect(result[:status]).to eq('healthy')
        expect(result[:details]['mounted']).to be true
        expect(result[:details]['share']).to eq('storage')
      end
    end
  end

  describe '#file_url' do
    it 'returns file:// URL' do
      result = provider.file_url(file_object)
      expect(result).to start_with('file://')
      expect(result).to include(file_object.storage_key)
    end
  end

  describe '#stream_file' do
    before do
      full_path = File.join(mount_path, file_object.storage_key)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, 'streaming test content')
    end

    it 'yields file chunks' do
      chunks = []
      provider.stream_file(file_object) { |chunk| chunks << chunk }

      expect(chunks.join).to eq('streaming test content')
    end
  end

  describe '#file_metadata' do
    before do
      full_path = File.join(mount_path, file_object.storage_key)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, 'metadata test')
    end

    it 'returns file metadata' do
      result = provider.file_metadata(file_object)

      expect(result['size']).to eq(13)
      expect(result).to have_key('created_at')
      expect(result).to have_key('modified_at')
    end
  end
end
