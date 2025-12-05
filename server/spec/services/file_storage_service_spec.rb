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
    FileUtils.rm_rf(storage.configuration['root_path']) if File.exist?(storage.configuration['root_path'])
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
      expect { described_class.new(account) }.to raise_error(ArgumentError, /No default storage/)
    end
  end

  describe '#upload_file' do
    let(:file_content) { 'Test file content' }
    let(:temp_file) do
      file = Tempfile.new(['test', '.txt'])
      file.write(file_content)
      file.rewind
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

    it 'validates file size' do
      large_file = Tempfile.new(['large', '.txt'])
      large_file.write('x' * 101.megabytes)
      large_file.rewind

      expect {
        service.upload_file(large_file, filename: 'large.txt', uploaded_by_id: user.id)
      }.to raise_error(/exceeds maximum/)

      large_file.close!
    end

    it 'checks quota before upload' do
      storage.update!(quota_bytes: 100)

      expect {
        service.upload_file(temp_file, filename: 'test.txt', uploaded_by_id: user.id)
      }.to raise_error(/quota exceeded/)
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

    it 'updates storage usage counters' do
      expect {
        service.upload_file(temp_file, filename: 'test.txt', uploaded_by_id: user.id)
      }.to change { storage.reload.files_count }.by(1)
        .and change { storage.reload.total_size_bytes }.by_at_least(file_content.bytesize)
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
  end

  describe '#download_file' do
    let(:file_object) { create(:file_object, account: account, file_storage: storage) }

    before do
      # Create actual file in storage
      file_path = File.join(storage.configuration['root_path'], file_object.storage_key)
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, 'Test content')
    end

    it 'downloads file content' do
      content = service.download_file(file_object)
      expect(content.read).to eq('Test content')
    end

    it 'raises error for non-existent file' do
      file_object.update!(storage_key: 'non/existent/file.txt')
      expect { service.download_file(file_object) }.to raise_error(/not found/)
    end
  end

  describe '#delete_file' do
    let(:file_object) { create(:file_object, account: account, file_storage: storage) }

    it 'soft deletes file by default' do
      service.delete_file(file_object, deleted_by_id: user.id)

      expect(file_object.reload.deleted_at).not_to be_nil
      expect(file_object.deleted_by).to eq(user)
    end

    it 'permanently deletes when specified' do
      expect {
        service.delete_file(file_object, permanent: true)
      }.to change { FileObject.count }.by(-1)
    end

    it 'updates storage counters on delete' do
      file_size = file_object.file_size

      expect {
        service.delete_file(file_object, permanent: true)
      }.to change { storage.reload.files_count }.by(-1)
        .and change { storage.reload.total_size_bytes }.by(-file_size)
    end
  end

  describe '#create_version' do
    let(:file_object) { create(:file_object, account: account, file_storage: storage) }
    let(:new_content) { 'Updated content' }
    let(:temp_file) do
      file = Tempfile.new(['updated', '.txt'])
      file.write(new_content)
      file.rewind
      file
    end

    after { temp_file.close! }

    it 'creates new version of file' do
      expect {
        service.create_version(
          file_object,
          temp_file,
          created_by_user: user,
          change_description: 'Updated content'
        )
      }.to change { file_object.file_versions.count }.by(1)
    end

    it 'updates version number' do
      new_file = service.create_version(
        file_object,
        temp_file,
        created_by_user: user
      )

      expect(new_file.version).to eq(file_object.version + 1)
    end

    it 'marks previous version as not latest' do
      service.create_version(file_object, temp_file, created_by_user: user)

      expect(file_object.reload.is_latest_version).to be false
    end
  end

  describe '#create_share' do
    let(:file_object) { create(:file_object, account: account, file_storage: storage) }

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
    let(:file_object) { create(:file_object, account: account, file_storage: storage) }

    it 'adds tags to file' do
      tags = service.add_tags(file_object, ['important', 'project-alpha'])

      expect(tags.map(&:name)).to contain_exactly('important', 'project-alpha')
      expect(file_object.file_tags.count).to eq(2)
    end

    it 'creates new tags if they do not exist' do
      expect {
        service.add_tags(file_object, ['new-tag'])
      }.to change { account.file_tags.count }.by(1)
    end

    it 'does not duplicate existing tags' do
      tag = create(:file_tag, account: account, name: 'existing')

      expect {
        service.add_tags(file_object, ['existing'])
      }.not_to change { account.file_tags.count }

      expect(file_object.file_tags).to include(tag)
    end
  end

  describe '#file_url' do
    let(:file_object) { create(:file_object, account: account, file_storage: storage) }

    it 'returns file URL' do
      url = service.file_url(file_object)
      expect(url).to be_present
    end

    it 'returns signed URL when requested' do
      url = service.file_url(file_object, signed: true, expires_in: 1.hour)
      expect(url).to be_present
    end
  end

  describe '#list_files' do
    before do
      create(:file_object, account: account, file_storage: storage, category: 'user_upload')
      create(:file_object, account: account, file_storage: storage, category: 'workflow_output')
      create(:file_object, account: account, file_storage: storage, visibility: 'public')
    end

    it 'lists all files' do
      files = service.list_files
      expect(files.count).to eq(3)
    end

    it 'filters by category' do
      files = service.list_files(category: 'user_upload')
      expect(files.count).to eq(1)
    end

    it 'filters by visibility' do
      files = service.list_files(visibility: 'public')
      expect(files.count).to eq(1)
    end

    it 'excludes deleted files by default' do
      create(:file_object, :deleted, account: account, file_storage: storage)
      files = service.list_files
      expect(files.count).to eq(3)
    end

    it 'includes deleted files when requested' do
      create(:file_object, :deleted, account: account, file_storage: storage)
      files = service.list_files(include_deleted: true)
      expect(files.count).to eq(4)
    end
  end

  describe 'quota management' do
    it 'returns available space' do
      storage.update!(quota_bytes: 1.gigabyte, total_size_bytes: 500.megabytes)
      expect(service.available_space_bytes).to eq(500.megabytes)
    end

    it 'returns unlimited when no quota' do
      storage.update!(quota_bytes: nil)
      expect(service.quota_enabled?).to be false
    end

    it 'calculates quota usage percentage' do
      storage.update!(quota_bytes: 1.gigabyte, total_size_bytes: 250.megabytes)
      expect(service.quota_usage_percent).to be_within(0.1).of(25.0)
    end
  end
end
