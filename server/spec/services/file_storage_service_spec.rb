# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FileStorageService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:storage) { create(:file_storage, :default, account: account) }
  let(:service) { described_class.new(account, storage_config: storage) }

  before do
    # Initialize storage directory
    storage.storage_provider.initialize_storage
  end

  after do
    # Clean up test storage directory
    FileUtils.rm_rf(storage.configuration['root_path']) if storage.configuration&.dig('root_path') && File.exist?(storage.configuration['root_path'])
  end

  describe '#initialize' do
    it 'initializes with account and storage config' do
      expect(service.account).to eq(account)
      expect(service.storage_config).to eq(storage)
    end

    it 'uses default storage when no config provided' do
      service_without_config = described_class.new(account)
      expect(service_without_config.storage_config).to eq(storage)
    end

    it 'raises error when no default storage exists' do
      storage.update!(is_default: false)
      expect { described_class.new(account) }.to raise_error(FileStorageService::StorageNotFoundError, /No storage configuration found/)
    end
  end

  describe '#upload_file' do
    let(:file_content) { 'Test file content' }
    let(:temp_file) do
      file = Tempfile.new([ 'test', '.txt' ])
      file.write(file_content)
      file.rewind
      # Add content_type method so detect_content_type doesn't use MIME::Types
      file.define_singleton_method(:content_type) { 'text/plain' }
      file
    end

    after { temp_file.close! }

    it 'uploads file successfully' do
      file_object = service.upload_file(
        temp_file,
        filename: 'test.txt',
        content_type: 'text/plain',
        uploaded_by_id: user.id
      )

      expect(file_object).to be_persisted
      expect(file_object.filename).to eq('test.txt')
      expect(file_object.content_type).to eq('text/plain')
      expect(file_object.file_size).to eq(file_content.bytesize)
      expect(file_object.uploaded_by).to eq(user)
    end

    it 'sets category and visibility' do
      file_object = service.upload_file(
        temp_file,
        filename: 'test.txt',
        category: 'workflow_output',
        visibility: 'public',
        uploaded_by_id: user.id
      )

      expect(file_object.category).to eq('workflow_output')
      expect(file_object.visibility).to eq('public')
    end

    it 'adds metadata to file object' do
      metadata = { 'source' => 'api', 'project' => 'test' }
      file_object = service.upload_file(
        temp_file,
        filename: 'test.txt',
        metadata: metadata,
        uploaded_by_id: user.id
      )

      expect(file_object.metadata).to include(metadata)
    end

    context 'with quota enabled' do
      before do
        # Setting quota_bytes enables quota checking (quota_enabled? returns true when quota_bytes is present)
        storage.update!(quota_bytes: 10) # Set quota smaller than file content
      end

      it 'raises quota exceeded error when file exceeds available space' do
        expect {
          service.upload_file(temp_file, filename: 'test.txt', uploaded_by_id: user.id)
        }.to raise_error(FileStorageService::QuotaExceededError, /quota exceeded/i)
      end
    end
  end

  describe '#download_file' do
    let(:file_object) { create(:file_object, account: account, storage: storage) }

    before do
      # Create actual file in storage
      root_path = storage.configuration&.dig('root_path') || '/tmp/test_storage'
      file_path = File.join(root_path, file_object.storage_key)
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, 'Test content')
    end

    it 'downloads file content' do
      content = service.download_file(file_object)
      # Service returns String directly, not IO
      expect(content).to eq('Test content')
    end

    it 'raises error for file from different account' do
      other_account = create(:account)
      other_file = create(:file_object, account: other_account, storage: storage)

      expect { service.download_file(other_file) }.to raise_error(FileStorageService::InvalidFileError, /different account/)
    end
  end

  describe '#delete_file' do
    let(:file_object) { create(:file_object, account: account, storage: storage) }

    before do
      # Create actual file in storage
      root_path = storage.configuration&.dig('root_path') || '/tmp/test_storage'
      file_path = File.join(root_path, file_object.storage_key)
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, 'Test content')

      # Mock provider delete to return true
      allow(storage.storage_provider).to receive(:delete_file).and_return(true)
    end

    it 'soft deletes file by default' do
      service.delete_file(file_object, deleted_by_user: user)

      expect(file_object.reload.deleted_at).not_to be_nil
    end

    it 'permanently deletes when specified' do
      expect {
        service.delete_file(file_object, permanent: true)
      }.to change { FileManagement::Object.count }.by(-1)
    end
  end

  describe '#create_share' do
    let(:file_object) { create(:file_object, account: account, storage: storage) }

    it 'creates file share with unique token' do
      share = service.create_share(file_object, created_by_id: user.id)

      expect(share).to be_persisted
      expect(share.share_token).to be_present
      expect(share.status).to eq('active')
    end

    it 'creates share with expiration' do
      expires_at = 7.days.from_now
      share = service.create_share(
        file_object,
        created_by_id: user.id,
        expires_at: expires_at
      )

      expect(share.expires_at).to be_within(1.second).of(expires_at)
    end

    it 'creates password-protected share' do
      share = service.create_share(
        file_object,
        created_by_id: user.id,
        password: 'secret123'
      )

      expect(share.password_digest).to be_present
    end

    it 'sets download limit' do
      share = service.create_share(
        file_object,
        created_by_id: user.id,
        max_downloads: 10
      )

      expect(share.max_downloads).to eq(10)
    end
  end

  describe '#add_tags' do
    let(:file_object) { create(:file_object, account: account, storage: storage) }

    it 'adds tags to file' do
      tags = service.add_tags(file_object, [ 'important', 'project-alpha' ])

      expect(tags.map(&:name)).to contain_exactly('important', 'project-alpha')
      expect(file_object.tags.count).to eq(2)
    end

    it 'creates new tags if they do not exist' do
      expect {
        service.add_tags(file_object, [ 'new-tag' ])
      }.to change { account.file_tags.count }.by(1)
    end

    it 'does not duplicate existing tags' do
      tag = create(:file_tag, account: account, name: 'existing')

      expect {
        service.add_tags(file_object, [ 'existing' ])
      }.not_to change { account.file_tags.count }

      expect(file_object.tags).to include(tag)
    end
  end

  describe '#file_url' do
    let(:file_object) { create(:file_object, account: account, storage: storage) }

    it 'returns file URL' do
      url = service.file_url(file_object)
      expect(url).to be_present
    end

    it 'returns signed URL when requested' do
      url = service.file_url(file_object, signed: true, expires_in: 1.hour)
      expect(url).to be_present
    end
  end

  describe '#storage_statistics' do
    it 'returns storage statistics from provider' do
      stats = service.storage_statistics
      expect(stats).to be_a(Hash)
    end
  end

  describe '#health_check' do
    it 'returns health check results' do
      result = service.health_check
      expect(result).to be_a(Hash)
    end
  end

  describe '#test_connection' do
    it 'returns connection test results' do
      result = service.test_connection
      expect(result).to be_a(Hash)
    end
  end
end
