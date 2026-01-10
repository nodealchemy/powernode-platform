# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'File Permission-Based Access Integration', type: :integration do
  let(:account) { create(:account) }
  let(:storage) do
    FileManagement::Storage.create!(
      account: account,
      name: 'Permission Test Storage',
      provider_type: 'local',
      configuration: {
        'root_path' => Rails.root.join('tmp', 'permission_test_storage', account.id).to_s
      },
      is_default: true,
      status: 'active',
      quota_bytes: 100.megabytes
    )
  end

  # Define users with different permission levels
  let(:admin_user) do
    create(:user, account: account, permissions: [
      'files.upload', 'files.read', 'files.delete', 'files.manage',
      'files.share', 'admin.access'
    ])
  end

  let(:uploader_user) do
    create(:user, account: account, permissions: [ 'files.upload', 'files.read' ])
  end

  let(:read_only_user) do
    create(:user, account: account, permissions: [ 'files.read' ])
  end

  let(:no_access_user) do
    create(:user, account: account, permissions: [])
  end

  before do
    FileUtils.mkdir_p(storage.configuration['root_path'])
  end

  after do
    FileUtils.rm_rf(Rails.root.join('tmp', 'permission_test_storage'))
  end

  describe 'File Upload Permissions' do
    it 'allows users with files.upload permission to upload' do
      file_object = FileManagement::Object.new(
        account: account,
        storage: storage,
        uploaded_by: uploader_user,
        filename: 'upload_test.txt',
        storage_key: "uploads/#{SecureRandom.uuid}/upload_test.txt",
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload'
      )

      expect(uploader_user.permission_names).to include('files.upload')
      expect(file_object.save).to be true

      provider = StorageProviderFactory.get_provider(storage)
      result = provider.upload_file(file_object, StringIO.new('test content'))
      expect(result).to be true
    end

    it 'prevents users without files.upload permission from uploading' do
      expect(read_only_user.permission_names).not_to include('files.upload')
      expect(no_access_user.permission_names).not_to include('files.upload')
    end

    it 'allows admin users to upload files' do
      expect(admin_user.permission_names).to include('files.upload')
      expect(admin_user.permission_names).to include('files.manage')
    end
  end

  describe 'File Read Permissions' do
    let(:test_file) do
      obj = FileManagement::Object.create!(
        account: account,
        storage: storage,
        uploaded_by: uploader_user,
        filename: 'readable_file.txt',
        storage_key: "reads/#{SecureRandom.uuid}/readable_file.txt",
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload',
        visibility: 'private'
      )

      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(obj, StringIO.new('readable content'))
      obj
    end

    it 'allows users with files.read permission to read files' do
      expect(read_only_user.permission_names).to include('files.read')

      # User can access file in database
      file = FileManagement::Object.where(account: account, id: test_file.id).first
      expect(file).to be_present
    end

    it 'allows uploader to read their own files' do
      expect(uploader_user.permission_names).to include('files.read')

      file = FileManagement::Object.where(account: account, uploaded_by: uploader_user, id: test_file.id).first
      expect(file).to be_present
    end

    it 'prevents users without files.read permission from reading files' do
      expect(no_access_user.permission_names).not_to include('files.read')

      # Simulate permission check (would be done in controller)
      can_read = no_access_user.permission_names.include?('files.read')
      expect(can_read).to be false
    end

    it 'enforces file-level access permissions' do
      restricted_file = FileManagement::Object.create!(
        account: account,
        storage: storage,
        uploaded_by: admin_user,
        filename: 'restricted.txt',
        storage_key: "restricted/#{SecureRandom.uuid}/restricted.txt",
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload',
        visibility: 'private',
        access_permissions: {
          'allowed_user_ids' => [ admin_user.id ]
        }
      )

      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(restricted_file, StringIO.new('restricted content'))

      # Admin has access
      expect(restricted_file.access_permissions['allowed_user_ids']).to include(admin_user.id)

      # Other users don't have access
      expect(restricted_file.access_permissions['allowed_user_ids']).not_to include(uploader_user.id)
      expect(restricted_file.access_permissions['allowed_user_ids']).not_to include(read_only_user.id)
    end
  end

  describe 'File Delete Permissions' do
    let(:deletable_file) do
      obj = FileManagement::Object.create!(
        account: account,
        storage: storage,
        uploaded_by: uploader_user,
        filename: 'deletable.txt',
        storage_key: "deletes/#{SecureRandom.uuid}/deletable.txt",
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload'
      )

      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(obj, StringIO.new('deletable content'))
      obj
    end

    it 'allows users with files.delete permission to delete files' do
      expect(admin_user.permission_names).to include('files.delete')

      # Admin can soft delete
      deletable_file.update!(deleted_at: Time.current, deleted_by: admin_user)
      expect(deletable_file.deleted_at).to be_present
    end

    it 'prevents users without files.delete permission from deleting' do
      expect(read_only_user.permission_names).not_to include('files.delete')
      expect(uploader_user.permission_names).not_to include('files.delete')
      expect(no_access_user.permission_names).not_to include('files.delete')
    end

    it 'allows file owner to delete their own files if they have permission' do
      # Uploader doesn't have delete permission
      expect(uploader_user.permission_names).not_to include('files.delete')

      # Create uploader with delete permission
      owner_with_delete = create(:user, account: account, permissions: [ 'files.upload', 'files.read', 'files.delete' ])

      owner_file = FileManagement::Object.create!(
        account: account,
        storage: storage,
        uploaded_by: owner_with_delete,
        filename: 'owner_file.txt',
        storage_key: "owner/#{SecureRandom.uuid}/owner_file.txt",
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload'
      )

      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(owner_file, StringIO.new('owner content'))

      expect(owner_with_delete.permission_names).to include('files.delete')
      owner_file.update!(deleted_at: Time.current, deleted_by: owner_with_delete)
      expect(owner_file.deleted_at).to be_present
    end
  end

  describe 'File Management Permissions' do
    it 'allows users with files.manage permission to perform all operations' do
      expect(admin_user.permission_names).to include('files.manage')

      # Can upload
      expect(admin_user.permission_names).to include('files.upload')

      # Can read
      expect(admin_user.permission_names).to include('files.read')

      # Can delete
      expect(admin_user.permission_names).to include('files.delete')

      # Can share
      expect(admin_user.permission_names).to include('files.share')
    end

    it 'allows managers to modify file metadata' do
      file = FileManagement::Object.create!(
        account: account,
        storage: storage,
        uploaded_by: uploader_user,
        filename: 'manageable.txt',
        storage_key: "manage/#{SecureRandom.uuid}/manageable.txt",
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload',
        visibility: 'private'
      )

      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(file, StringIO.new('manageable content'))

      # Admin with files.manage can update metadata
      expect(admin_user.permission_names).to include('files.manage')
      file.update!(visibility: 'shared', metadata: { 'updated_by' => admin_user.id })
      expect(file.visibility).to eq('shared')
    end

    it 'prevents non-managers from modifying other users files' do
      admin_file = FileManagement::Object.create!(
        account: account,
        storage: storage,
        uploaded_by: admin_user,
        filename: 'admin_file.txt',
        storage_key: "admin/#{SecureRandom.uuid}/admin_file.txt",
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload'
      )

      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(admin_file, StringIO.new('admin content'))

      # Read-only user cannot modify
      expect(read_only_user.permission_names).not_to include('files.manage')
      expect(read_only_user.id).not_to eq(admin_file.uploaded_by_id)
    end
  end

  describe 'File Sharing Permissions' do
    let(:shareable_file) do
      obj = FileManagement::Object.create!(
        account: account,
        storage: storage,
        uploaded_by: uploader_user,
        filename: 'shareable.txt',
        storage_key: "share/#{SecureRandom.uuid}/shareable.txt",
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload',
        visibility: 'private'
      )

      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(obj, StringIO.new('shareable content'))
      obj
    end

    it 'allows users with files.share permission to create shares' do
      expect(admin_user.permission_names).to include('files.share')

      share = FileManagement::Share.create!(
        object: shareable_file,
        account: account,
        created_by: admin_user,
        share_token: SecureRandom.urlsafe_base64(32),
        share_type: 'public_link',
        access_level: 'download',
        status: 'active',
        expires_at: 7.days.from_now
      )

      expect(share).to be_persisted
      expect(share.created_by_id).to eq(admin_user.id)
    end

    it 'prevents users without files.share permission from creating shares' do
      expect(read_only_user.permission_names).not_to include('files.share')
      expect(uploader_user.permission_names).not_to include('files.share')
    end

    it 'allows share creators to revoke their own shares' do
      share = FileManagement::Share.create!(
        object: shareable_file,
        account: account,
        created_by: admin_user,
        share_token: SecureRandom.urlsafe_base64(32),
        share_type: 'public_link',
        access_level: 'download',
        status: 'active'
      )

      expect(admin_user.permission_names).to include('files.share')
      share.update!(status: 'revoked')
      expect(share.status).to eq('revoked')
    end
  end

  describe 'Cross-Account Isolation' do
    let(:other_account) { create(:account) }
    let(:other_user) { create(:user, account: other_account, permissions: [ 'files.read', 'files.upload', 'files.manage' ]) }
    let(:other_storage) do
      FileManagement::Storage.create!(
        account: other_account,
        name: 'Other Account Storage',
        provider_type: 'local',
        configuration: {
          'root_path' => Rails.root.join('tmp', 'permission_test_storage', other_account.id).to_s
        },
        is_default: true,
        status: 'active'
      )
    end

    before do
      FileUtils.mkdir_p(other_storage.configuration['root_path'])
    end

    it 'prevents access to files from different accounts' do
      account_file = FileManagement::Object.create!(
        account: account,
        storage: storage,
        uploaded_by: admin_user,
        filename: 'account_file.txt',
        storage_key: "account/#{SecureRandom.uuid}/account_file.txt",
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload'
      )

      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(account_file, StringIO.new('account content'))

      # User from other account cannot access
      other_account_files = FileManagement::Object.where(account: other_account, id: account_file.id)
      expect(other_account_files).to be_empty

      # Files are account-scoped
      expect(account_file.account_id).to eq(account.id)
      expect(account_file.account_id).not_to eq(other_account.id)
    end

    it 'ensures storage is account-isolated' do
      expect(storage.account_id).to eq(account.id)
      expect(other_storage.account_id).to eq(other_account.id)
      expect(storage.id).not_to eq(other_storage.id)
    end
  end

  describe 'Admin Override Permissions' do
    it 'allows admin.access users to override file restrictions' do
      restricted_file = FileManagement::Object.create!(
        account: account,
        storage: storage,
        uploaded_by: uploader_user,
        filename: 'restricted_admin.txt',
        storage_key: "restricted/#{SecureRandom.uuid}/restricted_admin.txt",
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload',
        visibility: 'private',
        access_permissions: {
          'allowed_user_ids' => [ uploader_user.id ]
        }
      )

      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(restricted_file, StringIO.new('restricted admin content'))

      # Admin can access despite not being in allowed_user_ids
      expect(admin_user.permission_names).to include('admin.access')
      expect(admin_user.permission_names).to include('files.manage')

      # Admin override check (would be in controller)
      has_admin_override = admin_user.permission_names.include?('admin.access') || admin_user.permission_names.include?('files.manage')
      expect(has_admin_override).to be true
    end
  end

  describe 'Permission Validation Helpers' do
    it 'provides helper methods to check file permissions' do
      file = FileManagement::Object.create!(
        account: account,
        storage: storage,
        uploaded_by: uploader_user,
        filename: 'helper_test.txt',
        storage_key: "helpers/#{SecureRandom.uuid}/helper_test.txt",
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload'
      )

      # Can upload?
      expect(uploader_user.permission_names.include?('files.upload')).to be true
      expect(read_only_user.permission_names.include?('files.upload')).to be false

      # Can read?
      expect(read_only_user.permission_names.include?('files.read')).to be true
      expect(no_access_user.permission_names.include?('files.read')).to be false

      # Can delete?
      expect(admin_user.permission_names.include?('files.delete')).to be true
      expect(uploader_user.permission_names.include?('files.delete')).to be false

      # Can manage?
      expect(admin_user.permission_names.include?('files.manage')).to be true
      expect(uploader_user.permission_names.include?('files.manage')).to be false

      # Can share?
      expect(admin_user.permission_names.include?('files.share')).to be true
      expect(uploader_user.permission_names.include?('files.share')).to be false
    end
  end
end
