# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'File Management Flow Integration', type: :integration do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'files.upload', 'files.read', 'files.delete' ]) }
  let(:storage) do
    FileStorage.create!(
      account: account,
      name: 'Test Local Storage',
      provider_type: 'local',
      configuration: {
        'root_path' => Rails.root.join('tmp', 'test_storage', account.id).to_s
      },
      is_default: true,
      status: 'active',
      quota_bytes: 100.megabytes
    )
  end

  let(:test_file_path) { Rails.root.join('tmp', 'test_upload.txt') }
  let(:test_file_content) { 'This is a test file for integration testing.' }

  before do
    # Create test file
    FileUtils.mkdir_p(File.dirname(test_file_path))
    File.write(test_file_path, test_file_content)

    # Create storage directory
    FileUtils.mkdir_p(storage.configuration['root_path'])
  end

  after do
    # Cleanup
    FileUtils.rm_rf(Rails.root.join('tmp', 'test_storage'))
    FileUtils.rm_f(test_file_path)
  end

  describe 'Complete File Lifecycle' do
    it 'handles upload, read, download, and delete operations' do
      # Step 1: Upload file
      file_data = File.open(test_file_path, 'rb')

      file_object = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'test_upload.txt',
        storage_key: "uploads/#{SecureRandom.uuid}/test_upload.txt",
        content_type: 'text/plain',
        file_size: test_file_content.bytesize,
        file_type: 'document',
        category: 'user_upload',
        visibility: 'private'
      )

      provider = StorageProviderFactory.get_provider(storage)
      expect(provider.upload_file(file_object, file_data)).to be true
      file_data.close

      # Verify file was uploaded
      expect(provider.file_exists?(file_object)).to be true

      # Step 2: Read file content
      read_content = provider.read_file(file_object)
      expect(read_content).to eq(test_file_content)

      # Step 3: Get download URL
      download_url = provider.download_url(file_object)
      expect(download_url).to be_present
      expect(download_url).to include(file_object.storage_key)

      # Step 4: Update file metadata
      file_object.update!(download_count: file_object.download_count + 1)
      file_object.reload
      expect(file_object.download_count).to eq(1)

      # Step 5: Delete file
      expect(provider.delete_file(file_object)).to be true
      expect(provider.file_exists?(file_object)).to be false

      # Step 6: Soft delete in database
      file_object.update!(deleted_at: Time.current, deleted_by: user)
      expect(file_object.deleted_at).to be_present
    end

    it 'handles file versioning workflow' do
      # Create original file
      file_data = File.open(test_file_path, 'rb')

      original_file = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'versioned_document.txt',
        storage_key: "documents/#{SecureRandom.uuid}/versioned_document.txt",
        content_type: 'text/plain',
        file_size: test_file_content.bytesize,
        file_type: 'document',
        category: 'user_upload',
        version: 1,
        is_latest_version: true
      )

      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(original_file, file_data)
      file_data.close

      # Create version record
      FileVersion.create!(
        file_object: original_file,
        account: account,
        created_by: user,
        version_number: 1,
        storage_key: original_file.storage_key,
        file_size: original_file.file_size,
        checksum_sha256: provider.calculate_checksum(File.read(test_file_path))
      )

      # Upload new version
      updated_content = "#{test_file_content}\nUpdated content."
      updated_file_path = Rails.root.join('tmp', 'test_upload_v2.txt')
      File.write(updated_file_path, updated_content)

      new_version = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'versioned_document.txt',
        storage_key: "documents/#{SecureRandom.uuid}/versioned_document_v2.txt",
        content_type: 'text/plain',
        file_size: updated_content.bytesize,
        file_type: 'document',
        category: 'user_upload',
        version: 2,
        is_latest_version: true,
        parent_file_id: original_file.id
      )

      file_data = File.open(updated_file_path, 'rb')
      provider.upload_file(new_version, file_data)
      file_data.close

      # Mark original as not latest
      original_file.update!(is_latest_version: false)

      # Create version record for new version
      FileVersion.create!(
        file_object: new_version,
        account: account,
        created_by: user,
        version_number: 2,
        storage_key: new_version.storage_key,
        file_size: new_version.file_size,
        checksum_sha256: provider.calculate_checksum(updated_content)
      )

      # Verify version chain
      expect(new_version.parent_file_id).to eq(original_file.id)
      expect(new_version.version).to eq(2)
      expect(new_version.is_latest_version).to be true
      expect(original_file.is_latest_version).to be false

      # Verify both versions exist in storage
      expect(provider.file_exists?(original_file)).to be true
      expect(provider.file_exists?(new_version)).to be true

      FileUtils.rm_f(updated_file_path)
    end

    it 'handles file sharing workflow' do
      # Upload file
      file_data = File.open(test_file_path, 'rb')

      file_object = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'shared_document.txt',
        storage_key: "shared/#{SecureRandom.uuid}/shared_document.txt",
        content_type: 'text/plain',
        file_size: test_file_content.bytesize,
        file_type: 'document',
        category: 'user_upload',
        visibility: 'shared'
      )

      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(file_object, file_data)
      file_data.close

      # Create public share
      share = FileShare.create!(
        file_object: file_object,
        account: account,
        created_by: user,
        share_token: SecureRandom.urlsafe_base64(32),
        share_type: 'public_link',
        access_level: 'download',
        status: 'active',
        expires_at: 7.days.from_now,
        max_downloads: 10
      )

      # Simulate download via share
      share.update!(
        download_count: share.download_count + 1,
        last_accessed_at: Time.current,
        access_log: share.access_log + [ {
          accessed_at: Time.current.iso8601,
          ip_address: '127.0.0.1'
        } ]
      )

      expect(share.download_count).to eq(1)
      expect(share.access_log.length).to eq(1)
      expect(share.status).to eq('active')

      # Simulate max downloads reached
      share.update!(download_count: 10)
      expect(share.download_count).to eq(share.max_downloads)

      # Revoke share
      share.update!(status: 'revoked')
      expect(share.status).to eq('revoked')
    end

    it 'handles storage quota enforcement' do
      # Set low quota
      storage.update!(quota_bytes: 100.bytes)

      # Try to upload file that exceeds quota
      large_content = 'a' * 200
      large_file_path = Rails.root.join('tmp', 'large_file.txt')
      File.write(large_file_path, large_content)

      file_object = FileObject.new(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'large_file.txt',
        storage_key: "uploads/#{SecureRandom.uuid}/large_file.txt",
        content_type: 'text/plain',
        file_size: large_content.bytesize,
        file_type: 'document',
        category: 'user_upload'
      )

      # Check available space
      available_space = storage.available_space_bytes
      expect(available_space).to eq(100) # quota_bytes - total_size_bytes (0)

      # Verify quota would be exceeded
      expect(file_object.file_size).to be > available_space

      FileUtils.rm_f(large_file_path)
    end
  end

  describe 'Multi-User File Access' do
    let(:admin_user) { create(:user, account: account, permissions: [ 'files.upload', 'files.read', 'files.delete', 'files.manage' ]) }
    let(:read_only_user) { create(:user, account: account, permissions: [ 'files.read' ]) }
    let(:no_access_user) { create(:user, account: account, permissions: []) }

    it 'enforces permission-based access control' do
      # Admin uploads file
      file_data = File.open(test_file_path, 'rb')

      file_object = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: admin_user,
        filename: 'protected_document.txt',
        storage_key: "protected/#{SecureRandom.uuid}/protected_document.txt",
        content_type: 'text/plain',
        file_size: test_file_content.bytesize,
        file_type: 'document',
        category: 'user_upload',
        visibility: 'private',
        access_permissions: {
          'allowed_user_ids' => [ admin_user.id, read_only_user.id ]
        }
      )

      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(file_object, file_data)
      file_data.close

      # Admin can access
      expect(admin_user.permission_names).to include('files.read')
      expect(file_object.access_permissions['allowed_user_ids']).to include(admin_user.id)

      # Read-only user can access
      expect(read_only_user.permission_names).to include('files.read')
      expect(file_object.access_permissions['allowed_user_ids']).to include(read_only_user.id)

      # No-access user cannot access
      expect(no_access_user.permission_names).not_to include('files.read')
      expect(file_object.access_permissions['allowed_user_ids']).not_to include(no_access_user.id)

      # Only admin can delete
      expect(admin_user.permission_names).to include('files.delete')
      expect(read_only_user.permission_names).not_to include('files.delete')
      expect(no_access_user.permission_names).not_to include('files.delete')
    end
  end

  describe 'File Processing Workflow' do
    it 'handles async file processing jobs' do
      # Upload image file
      file_data = File.open(test_file_path, 'rb')

      file_object = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'test_image.jpg',
        storage_key: "images/#{SecureRandom.uuid}/test_image.jpg",
        content_type: 'image/jpeg',
        file_size: test_file_content.bytesize,
        file_type: 'image',
        category: 'user_upload',
        processing_status: 'pending'
      )

      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(file_object, file_data)
      file_data.close

      # Create processing job
      processing_job = FileProcessingJob.create!(
        file_object: file_object,
        account: account,
        job_type: 'thumbnail',
        status: 'pending',
        priority: 50,
        job_parameters: {
          'width' => 200,
          'height' => 200,
          'quality' => 85
        }
      )

      # Simulate job processing
      processing_job.update!(
        status: 'processing',
        started_at: Time.current
      )
      file_object.update!(processing_status: 'processing')

      # Simulate job completion
      processing_job.update!(
        status: 'completed',
        completed_at: Time.current,
        duration_ms: 150,
        result_data: {
          'thumbnail_key' => "thumbnails/#{file_object.id}/thumb.jpg"
        },
        output_storage_key: "thumbnails/#{file_object.id}/thumb.jpg"
      )
      file_object.update!(
        processing_status: 'completed',
        processing_metadata: {
          'thumbnail_generated' => true,
          'thumbnail_key' => processing_job.output_storage_key
        }
      )

      expect(processing_job.status).to eq('completed')
      expect(processing_job.duration_ms).to be_present
      expect(file_object.processing_status).to eq('completed')
      expect(file_object.processing_metadata['thumbnail_generated']).to be true
    end
  end

  describe 'Batch Operations' do
    it 'handles batch file deletion' do
      # Upload multiple files
      file_objects = 3.times.map do |i|
        file_data = File.open(test_file_path, 'rb')

        file_obj = FileObject.create!(
          account: account,
          file_storage: storage,
          uploaded_by: user,
          filename: "test_file_#{i}.txt",
          storage_key: "batch/#{SecureRandom.uuid}/test_file_#{i}.txt",
          content_type: 'text/plain',
          file_size: test_file_content.bytesize,
          file_type: 'document',
          category: 'user_upload'
        )

        provider = StorageProviderFactory.get_provider(storage)
        provider.upload_file(file_obj, file_data)
        file_data.close

        file_obj
      end

      # Verify all files exist
      provider = StorageProviderFactory.get_provider(storage)
      file_objects.each do |file_obj|
        expect(provider.file_exists?(file_obj)).to be true
      end

      # Batch delete
      results = provider.batch_delete(file_objects)

      expect(results[:success].length).to eq(3)
      expect(results[:failed].length).to eq(0)

      # Verify all files deleted
      file_objects.each do |file_obj|
        expect(provider.file_exists?(file_obj)).to be false
      end
    end
  end
end
