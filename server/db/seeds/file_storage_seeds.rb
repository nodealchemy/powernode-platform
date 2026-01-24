# frozen_string_literal: true

# File Storage Seeds - Create default local storage for all accounts
Rails.logger.info "🗄️  Seeding file storage configurations..."

Account.find_each do |account|
  # Skip if account already has a default storage
  if account.file_storages.where(is_default: true).exists?
    Rails.logger.info "  ↪ Account #{account.name} already has default storage"
    next
  end

  # Create local storage configuration
  storage = FileManagement::Storage.create!(
    account: account,
    name: 'Local Storage',
    provider_type: 'local',
    status: 'active',
    priority: 100,
    configuration: {
      'root_path' => Rails.root.join('storage', 'files', account.id).to_s
    },
    capabilities: {
      'max_file_size' => 100.megabytes,
      'supported_formats' => [ 'image/*', 'application/pdf', 'text/*', 'video/*', 'audio/*' ],
      'features' => [ 'versioning', 'sharing', 'tagging', 'processing' ]
    },
    quota_bytes: 10.gigabytes,
    is_default: true
  )

  # Initialize storage directory
  begin
    FileUtils.mkdir_p(storage.configuration['root_path'])
    Rails.logger.info "  ✅ Created default storage for #{account.name} (ID: #{storage.id})"
  rescue => e
    Rails.logger.error "  ❌ Failed to initialize storage for #{account.name}: #{e.message}"
    storage.update(status: 'failed', health_status: 'failed')
  end
end

Rails.logger.info "✅ File storage seed complete!"
