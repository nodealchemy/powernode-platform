# frozen_string_literal: true

class AddSystemModelEnhancements < ActiveRecord::Migration[8.0]
  def change
    # ==========================================================================
    # RAID Support for Provider Volumes
    # ==========================================================================
    change_table :system_provider_volumes do |t|
      t.integer :raid_level, default: nil, comment: 'RAID level (0 for striping, 1 for mirroring)'
      t.bigint :used_bytes, default: 0, comment: 'Used space in bytes'
      t.bigint :capacity_bytes, comment: 'Total capacity in bytes'
    end

    # Provider Volume Members for RAID configurations
    create_table :system_provider_volume_members, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :provider_volume, type: :uuid, foreign_key: { to_table: :system_provider_volumes }, null: false
      t.string :cloud_volume_id, comment: 'Cloud provider volume ID for this member'
      t.string :device_name, comment: 'Device name (e.g., /dev/sdb)'
      t.string :status, default: 'pending', null: false
      t.integer :size_gb, null: false
      t.integer :member_index, default: 0, comment: 'Order in RAID array'
      t.jsonb :config, default: {}

      t.timestamps
    end

    add_index :system_provider_volume_members, [:provider_volume_id, :member_index],
              unique: true, name: 'idx_volume_members_volume_index'
    add_index :system_provider_volume_members, :cloud_volume_id

    # ==========================================================================
    # Boot Image Enhancements for Node Architecture
    # ==========================================================================
    change_table :system_node_architectures do |t|
      t.string :kernel_checksum, comment: 'SHA256 checksum of kernel file'
      t.string :ramdisk_checksum, comment: 'SHA256 checksum of ramdisk file'
      t.string :image_checksum, comment: 'SHA256 checksum of boot image file'
      t.string :kernel_version, comment: 'Kernel version string'
      t.string :image_format, comment: 'Image format (raw, qcow2, vmdk, etc.)'
    end

    # ==========================================================================
    # Geolocation for Node Instances
    # ==========================================================================
    change_table :system_node_instances do |t|
      t.decimal :latitude, precision: 10, scale: 7, comment: 'Latitude coordinate'
      t.decimal :longitude, precision: 10, scale: 7, comment: 'Longitude coordinate'
      t.string :mac_address, comment: 'Primary MAC address'
      t.boolean :private_netboot, default: false, comment: 'Enable private netboot'
    end

    add_index :system_node_instances, :mac_address, unique: true, where: "mac_address IS NOT NULL"

    # ==========================================================================
    # Additional Node Enhancements
    # ==========================================================================
    change_table :system_nodes do |t|
      t.integer :runtime_amount, default: 0, comment: 'Runtime tracking in minutes'
      t.boolean :tmpfs_store, default: false, comment: 'Use tmpfs for storage'
    end
  end
end
