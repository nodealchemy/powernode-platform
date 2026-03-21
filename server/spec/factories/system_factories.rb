# frozen_string_literal: true

FactoryBot.define do
  # System::Provider
  factory :system_provider, class: "System::Provider" do
    association :account
    sequence(:name) { |n| "Provider #{n}" }
    provider_type { "aws" }
    enabled { true }
    config { {} }
    capabilities { {} }
  end

  # System::ProviderRegion
  factory :system_provider_region, class: "System::ProviderRegion" do
    association :account
    association :provider, factory: :system_provider
    sequence(:name) { |n| "Region #{n}" }
    sequence(:region_code) { |n| "us-east-#{n}" }
    enabled { true }
    capabilities { {} }
  end

  # System::ProviderConnection
  factory :system_provider_connection, class: "System::ProviderConnection" do
    association :account
    association :provider, factory: :system_provider
    sequence(:name) { |n| "Connection #{n}" }
    access_key { "test-access-key" }
    secret_key { "test-secret-key" }
    status { "connected" }
    config { {} }
  end

  # System::ProviderAvailabilityZone
  factory :system_provider_availability_zone, class: "System::ProviderAvailabilityZone" do
    association :provider_region, factory: :system_provider_region
    sequence(:name) { |n| "us-east-1#{('a'.ord + n % 6).chr}" }
    zone_code { name }
    enabled { true }
  end

  # System::ProviderInstanceType
  factory :system_provider_instance_type, class: "System::ProviderInstanceType" do
    association :account
    association :provider, factory: :system_provider
    sequence(:name) { |n| "t#{n}.micro" }
    sequence(:instance_type_code) { |n| "t#{n}.micro" }
    vcpus { 1 }
    memory_mb { 1024 }
    storage_gb { 8 }
    enabled { true }
    specs { {} }
  end

  # System::NodeArchitecture
  factory :system_node_architecture, class: "System::NodeArchitecture" do
    association :account
    sequence(:name) { |n| "Architecture #{n}" }
    kernel_options { "" }
    enabled { true }
    public { false }

    trait :with_checksums do
      kernel_checksum { Digest::SHA256.hexdigest("kernel_data") }
      ramdisk_checksum { Digest::SHA256.hexdigest("ramdisk_data") }
      image_checksum { Digest::SHA256.hexdigest("image_data") }
      kernel_version { "5.15.0-generic" }
      image_format { "qcow2" }
    end
  end

  # System::NodePlatform
  factory :system_node_platform, class: "System::NodePlatform" do
    association :account
    association :node_architecture, factory: :system_node_architecture
    sequence(:name) { |n| "Platform #{n}" }
    enabled { true }
    public { false }
    build_script { "#!/bin/bash\necho 'build'" }
    init_script { "#!/bin/bash\necho 'init'" }
    sync_script { "#!/bin/bash\necho 'sync'" }
  end

  # System::NodeTemplate
  factory :system_node_template, class: "System::NodeTemplate" do
    association :account
    association :node_platform, factory: :system_node_platform
    sequence(:name) { |n| "Template #{n}" }
    enabled { true }
    public { false }
    admin_user { "admin" }
    config { {} }
  end

  # System::Node
  factory :system_node, class: "System::Node" do
    association :account
    association :node_template, factory: :system_node_template
    sequence(:name) { |n| "Node #{n}" }
    enabled { true }
    config { {} }
    allocate_public_ip { false }
    runtime_amount { 0 }
    tmpfs_store { false }

    trait :with_runtime do
      runtime_amount { 120 } # 2 hours in minutes
    end

    trait :with_tmpfs do
      tmpfs_store { true }
    end
  end

  # System::NodeInstance
  factory :system_node_instance, class: "System::NodeInstance" do
    association :node, factory: :system_node
    association :provider_region, factory: :system_provider_region
    association :provider_instance_type, factory: :system_provider_instance_type
    sequence(:name) { |n| "Instance #{n}" }
    variety { "cloud" }
    status { "pending" }
    config { {} }

    trait :running do
      status { "running" }
      private_ip_address { "10.0.1.#{rand(1..254)}" }
      public_ip_address { "203.0.113.#{rand(1..254)}" }
    end

    trait :stopped do
      status { "stopped" }
    end

    trait :physical do
      variety { "physical" }
    end

    trait :with_coordinates do
      latitude { 37.7749 }
      longitude { -122.4194 }
    end

    trait :with_mac_address do
      mac_address { "00:11:22:33:44:55" }
    end

    trait :with_netboot do
      variety { "physical" }
      mac_address { "00:11:22:33:44:55" }
      private_netboot { true }
    end
  end

  # System::ProviderVolumeType
  factory :system_provider_volume_type, class: "System::ProviderVolumeType" do
    association :account
    association :provider, factory: :system_provider
    sequence(:name) { |n| "gp#{n}" }
    volume_type { "gp2" }
    min_size_gb { 1 }
    max_size_gb { 16384 }
    min_iops { nil }
    max_iops { nil }
    enabled { true }
  end

  # System::ProviderVolume
  factory :system_provider_volume, class: "System::ProviderVolume" do
    association :account
    association :provider_region, factory: :system_provider_region
    association :volume_type, factory: :system_provider_volume_type
    sequence(:name) { |n| "Volume #{n}" }
    size_gb { 100 }
    status { "available" }

    trait :attached do
      status { "attached" }
      cloud_volume_id { "vol-#{SecureRandom.hex(8)}" }
    end

    trait :raid0 do
      raid_level { 0 }
      after(:create) do |volume|
        create_list(:system_provider_volume_member, 2, provider_volume: volume, status: "available")
      end
    end

    trait :raid1 do
      raid_level { 1 }
      after(:create) do |volume|
        create_list(:system_provider_volume_member, 2, provider_volume: volume, status: "available")
      end
    end
  end

  # System::ProviderVolumeMember
  factory :system_provider_volume_member, class: "System::ProviderVolumeMember" do
    association :provider_volume, factory: :system_provider_volume
    cloud_volume_id { "vol-#{SecureRandom.hex(8)}" }
    device_name { "/dev/sd#{('b'.ord + (rand(24))).chr}" }
    status { "pending" }
    size_gb { 100 }
    sequence(:member_index) { |n| n - 1 }
    config { {} }

    trait :available do
      status { "available" }
    end

    trait :attached do
      status { "attached" }
    end
  end

  # System::ProviderNetwork
  factory :system_provider_network, class: "System::ProviderNetwork" do
    association :account
    association :provider_region, factory: :system_provider_region
    sequence(:name) { |n| "Network #{n}" }
    cidr_block { "10.0.0.0/16" }
    status { "available" }
    config { {} }
  end

  # System::ProviderNetworkSubnet
  factory :system_provider_network_subnet, class: "System::ProviderNetworkSubnet" do
    association :provider_network, factory: :system_provider_network
    association :provider_availability_zone, factory: :system_provider_availability_zone
    sequence(:name) { |n| "Subnet #{n}" }
    cidr_block { "10.0.1.0/24" }
    status { "available" }
    config { {} }
  end

  # System::NodeModuleCategory
  factory :system_node_module_category, class: "System::NodeModuleCategory" do
    association :account
    sequence(:name) { |n| "Category #{n}" }
    enabled { true }
  end

  # System::NodeModule
  factory :system_node_module, class: "System::NodeModule" do
    association :account
    association :node_platform, factory: :system_node_platform
    association :category, factory: :system_node_module_category
    sequence(:name) { |n| "Module #{n}" }
    variety { "config" }
    enabled { true }
    public { false }
    priority { 50 }
    mask { {} }
    file_spec { {} }
    package_spec { {} }
    config { {} }
    lock_spec { false }
    current_version_number { 0 }

    trait :locked do
      lock_spec { true }
    end

    trait :with_data_file do
      data_file_name { "module_data.tar.gz" }
      data_checksum { Digest::SHA256.hexdigest("test data") }
      data_file_size { 1024 }
    end

    trait :versioned do
      after(:create) do |node_module|
        create(:system_node_module_version, node_module: node_module, version_number: 1)
        node_module.reload
      end
    end
  end

  # System::NodeModuleVersion
  factory :system_node_module_version, class: "System::NodeModuleVersion" do
    association :node_module, factory: :system_node_module
    sequence(:version_number) { |n| n }
    changelog { "Version changelog" }
    mask { {} }
    file_spec { {} }
    package_spec { {} }
    config { {} }

    trait :with_data_file do
      data_file_name { "module_v1.tar.gz" }
      data_checksum { Digest::SHA256.hexdigest("version data") }
      data_file_size { 2048 }
    end

    trait :with_creator do
      association :created_by, factory: :user
    end
  end

  # System::NodeScript
  factory :system_node_script, class: "System::NodeScript" do
    association :account
    sequence(:name) { |n| "Script #{n}" }
    variety { "custom" }
    data { "#!/bin/bash\necho 'hello'" }
    enabled { true }
    public { false }
  end

  # System::Operation
  factory :system_operation, class: "System::Operation" do
    association :account
    association :operable, factory: :system_node
    command { "sync" }
    status { "pending" }
    progress { 0 }
    events { [] }
    options { {} }

    trait :running do
      status { "running" }
      progress { 50 }
      started_at { 1.minute.ago }
    end

    trait :complete do
      status { "complete" }
      progress { 100 }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      error_message { "Operation failed" }
    end
  end

  # System::PuppetModule
  factory :system_puppet_module, class: "System::PuppetModule" do
    association :account
    sequence(:name) { |n| "puppet-module-#{n}" }
    enabled { true }
    public { false }
  end

  # System::PuppetResource
  factory :system_puppet_resource, class: "System::PuppetResource" do
    association :puppet_module, factory: :system_puppet_module
    sequence(:name) { |n| "resource-#{n}" }
    path { "/etc/puppet/modules" }
    data { "file { '/tmp/test': ensure => present }" }
    enabled { true }
  end

  # System::NodeModuleAssignment
  factory :system_node_module_assignment, class: "System::NodeModuleAssignment" do
    association :node, factory: :system_node
    association :node_module, factory: :system_node_module
    enabled { true }
  end

  # System::ModuleDependency
  factory :system_module_dependency, class: "System::ModuleDependency" do
    association :node_module, factory: :system_node_module
    association :dependency, factory: :system_node_module
    required { true }
    dependency_type { "requires" }
  end

  # System::TemplateModule
  factory :system_template_module, class: "System::TemplateModule" do
    association :node_template, factory: :system_node_template
    association :node_module, factory: :system_node_module
    enabled { true }
    priority { 50 }
  end

  # System::ProviderVolumeSnapshot
  factory :system_provider_volume_snapshot, class: "System::ProviderVolumeSnapshot" do
    association :account
    association :volume, factory: :system_provider_volume
    sequence(:name) { |n| "Snapshot #{n}" }
    status { "completed" }
    size_gb { 100 }
    progress { 100 }
  end

  # System::NodeMountPoint
  factory :system_node_mount_point, class: "System::NodeMountPoint" do
    association :account
    sequence(:name) { |n| "Mount #{n}" }
    mount_path { "/mnt/data" }
    mount_type { "nfs" }
    source { "server:/share" }
    options { { options: "defaults" } }
    enabled { true }
    auto_mount { true }
  end

  # System::InstanceMountPoint
  factory :system_instance_mount_point, class: "System::InstanceMountPoint" do
    association :node_instance, factory: :system_node_instance
    association :mount_point, factory: :system_node_mount_point
    enabled { true }
    config { {} }
  end

  # System::ModulePuppetAssignment
  factory :system_module_puppet_assignment, class: "System::ModulePuppetAssignment" do
    association :node_module, factory: :system_node_module
    association :puppet_module, factory: :system_puppet_module
    enabled { true }
    priority { 50 }
  end

  # System::NodeModuleCopyPath
  factory :system_node_module_copy_path, class: "System::NodeModuleCopyPath" do
    association :account
    sequence(:name) { |n| "CopyPath #{n}" }
    path { "/opt/modules" }
    enabled { true }
  end
end
