# frozen_string_literal: true

# Consolidated migration for Powernode System - Providers
# Combines: providers, provider_regions, provider_connections, provider_availability_zones,
#           provider_instance_types, region_instance_types
class CreatePowernodeSystemProviders < ActiveRecord::Migration[8.0]
  def change
    # ============ System::Provider ============
    create_table :system_providers, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true

      # Core fields
      t.string :name, null: false
      t.text :description
      t.string :provider_type, null: false  # aws, openstack, gcp, azure, digitalocean, custom

      # Status flags
      t.boolean :enabled, null: false, default: true
      t.boolean :public, null: false, default: false

      # Configuration and capabilities
      t.jsonb :config, null: false, default: {}
      t.jsonb :capabilities, null: false, default: {}

      t.timestamps

      t.index [:account_id, :name], unique: true
      t.index [:account_id, :provider_type]
      t.index [:account_id, :enabled]
      t.index :config, using: :gin
      t.index :capabilities, using: :gin
    end

    # ============ System::ProviderRegion ============
    create_table :system_provider_regions, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :provider, type: :uuid, null: false,
                   foreign_key: { to_table: :system_providers }

      # Core fields
      t.string :name, null: false
      t.text :description
      t.string :region_code, null: false
      t.string :endpoint_url

      # Image references
      t.string :kernel_image
      t.string :machine_image
      t.string :ramdisk_image

      # Status and capabilities
      t.boolean :enabled, null: false, default: true
      t.jsonb :capabilities, null: false, default: {}

      t.timestamps

      t.index [:provider_id, :region_code], unique: true
      t.index [:account_id, :enabled]
      t.index :capabilities, using: :gin
    end

    # ============ System::ProviderConnection ============
    create_table :system_provider_connections, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :provider, type: :uuid, null: false,
                   foreign_key: { to_table: :system_providers }

      # Core fields
      t.string :name, null: false
      t.text :description
      t.string :endpoint_url

      # Credentials (encrypted at application level)
      t.text :access_key_ciphertext
      t.text :secret_key_ciphertext
      t.string :tenant

      # Status
      t.boolean :enabled, null: false, default: true
      t.string :status, null: false, default: 'pending'  # pending, connected, error

      # Configuration
      t.jsonb :config, null: false, default: {}

      # Connection health
      t.datetime :last_tested_at
      t.string :last_test_status
      t.text :last_test_message

      t.timestamps

      t.index [:account_id, :name], unique: true
      t.index [:provider_id, :enabled]
      t.index :status
      t.index :config, using: :gin
    end

    add_check_constraint :system_provider_connections,
      "status IN ('pending', 'connected', 'error')",
      name: 'system_provider_connections_status_check'

    # ============ System::ProviderAvailabilityZone ============
    create_table :system_provider_availability_zones, id: :uuid do |t|
      t.references :provider_region, type: :uuid, null: false,
                   foreign_key: { to_table: :system_provider_regions }

      # Core fields
      t.string :name, null: false
      t.text :description
      t.string :zone_code, null: false

      # Status
      t.boolean :enabled, null: false, default: true
      t.string :status, null: false, default: 'available'  # available, impaired, unavailable

      # Capabilities
      t.jsonb :capabilities, null: false, default: {}

      t.timestamps

      t.index [:provider_region_id, :zone_code], unique: true
      t.index [:provider_region_id, :enabled]
      t.index :status
      t.index :capabilities, using: :gin
    end

    add_check_constraint :system_provider_availability_zones,
      "status IN ('available', 'impaired', 'unavailable')",
      name: 'system_provider_availability_zones_status_check'

    # ============ System::ProviderInstanceType ============
    create_table :system_provider_instance_types, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :provider, type: :uuid, null: false,
                   foreign_key: { to_table: :system_providers }

      # Core fields
      t.string :name, null: false
      t.text :description
      t.string :instance_type_code, null: false  # e.g., t2.micro, m5.large

      # Specifications
      t.integer :vcpus
      t.integer :memory_mb
      t.integer :storage_gb
      t.string :network_performance
      t.string :processor_type

      # Pricing (optional, for reference)
      t.decimal :hourly_price, precision: 10, scale: 4
      t.string :currency, default: 'USD'

      # Status
      t.boolean :enabled, null: false, default: true
      t.boolean :public, null: false, default: false

      # Additional specs
      t.jsonb :specs, null: false, default: {}

      t.timestamps

      t.index [:provider_id, :instance_type_code], unique: true
      t.index [:account_id, :enabled]
      t.index :specs, using: :gin
    end

    # ============ System::RegionInstanceType (Join Table) ============
    create_table :system_region_instance_types, id: :uuid do |t|
      t.references :provider_region, type: :uuid, null: false,
                   foreign_key: { to_table: :system_provider_regions }
      t.references :provider_instance_type, type: :uuid, null: false,
                   foreign_key: { to_table: :system_provider_instance_types }

      # Availability in this region
      t.boolean :available, null: false, default: true

      # Region-specific pricing (may differ from base price)
      t.decimal :hourly_price, precision: 10, scale: 4
      t.string :currency, default: 'USD'

      t.timestamps

      t.index [:provider_region_id, :provider_instance_type_id],
              unique: true,
              name: 'idx_region_instance_types_unique'
      t.index [:provider_region_id, :available]
    end

    # Add foreign keys to node_instances (must exist from node_core migration)
    add_foreign_key :system_node_instances, :system_provider_regions, column: :provider_region_id
    add_foreign_key :system_node_instances, :system_provider_instance_types, column: :provider_instance_type_id
  end
end
