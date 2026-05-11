# frozen_string_literal: true

FactoryBot.define do
  factory :file_storage, class: "FileManagement::Storage" do
    account
    sequence(:name) { |n| "Test Storage #{n}" }
    provider_type { 'local' }
    status { 'active' }
    priority { 100 }

    configuration do
      {
        'root_path' => Rails.root.join('tmp', 'test_storage', SecureRandom.hex(8)).to_s
      }
    end

    capabilities do
      {
        'max_file_size' => 100.megabytes,
        'supported_formats' => [ 'image/*', 'application/pdf', 'text/*' ],
        'features' => [ 'versioning', 'sharing', 'tagging' ]
      }
    end

    quota_bytes { 1.gigabyte }
    files_count { 0 }
    total_size_bytes { 0 }
    is_default { false }

    trait :default do
      is_default { true }
    end

    trait :with_quota do
      quota_bytes { 500.megabytes }
    end

    trait :s3 do
      provider_type { 's3' }
      configuration do
        {
          'bucket' => 'test-bucket',
          'region' => 'us-east-1',
          'access_key_id' => 'encrypted:test_key',
          'secret_access_key' => 'encrypted:test_secret'
        }
      end
    end

    trait :gcs do
      provider_type { 'gcs' }
      configuration do
        {
          'bucket' => 'test-bucket',
          'project_id' => 'test-project',
          'location' => 'US',
          'service_account_json' => '{"type": "service_account", "project_id": "test-project"}'
        }
      end
    end

    trait :azure do
      provider_type { 'azure' }
      configuration do
        {
          'container' => 'test-container',
          'storage_account_name' => 'teststorageaccount',
          'account_name' => 'teststorageaccount', # alias for provider compatibility
          'account_key' => 'dGVzdGtleQ==' # base64 encoded 'testkey'
        }
      end
    end

    trait :nfs do
      provider_type { 'nfs' }
      configuration do
        {
          'mount_path' => Rails.root.join('tmp', 'test_nfs_storage').to_s,
          'server_address' => '192.168.1.100',
          'share_path' => '/exports/storage'
        }
      end
    end

    trait :smb do
      provider_type { 'smb' }
      configuration do
        {
          'mount_path' => Rails.root.join('tmp', 'test_smb_storage').to_s,
          'server_address' => '192.168.1.200',
          'share_name' => 'storage',
          'username' => 'testuser',
          'domain' => 'WORKGROUP'
        }
      end
    end

    trait :inactive do
      status { 'inactive' }
    end

    trait :maintenance do
      status { 'maintenance' }
    end

    trait :healthy do
      health_status { 'healthy' }
      last_health_check_at { Time.current }
      health_details { { 'last_check' => 'passed', 'connectivity' => 'ok' } }
    end

    # Phase S1+ — storage opted in for per-instance node mounts.
    trait :node_mountable do
      node_mount_capable { true }
      requires_node_credentials { true }
      encryption_mode { 'fscrypt' }
      deployment_shape { 'self_hosted' }
    end

    # Phase S1+ — Shape 2 gateway proxy fronting an external NFS server.
    # Provide :gateway_node_instance_id when creating in tests.
    trait :gateway_proxy do
      provider_type { 'nfs' }
      node_mount_capable { true }
      requires_node_credentials { true }
      deployment_shape { 'gateway_proxy' }
      configuration do
        {
          'gateway_node_instance_id' => SecureRandom.uuid,
          'upstream_source_host' => '10.20.30.40',
          'upstream_export_path' => '/srv/data',
          're_export_path' => '/var/lib/powernode/storage/test',
          'upstream_mount_options' => %w[vers=4.2 proto=tcp hard]
        }
      end
    end
  end
end
