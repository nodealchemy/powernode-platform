# frozen_string_literal: true

class ExtendFileStoragesForNodeMountCapability < ActiveRecord::Migration[8.0]
  def change
    add_column :file_storages, :encryption_mode, :string, null: false, default: "none"
    add_column :file_storages, :default_mount_options, :jsonb, null: false, default: {}
    add_column :file_storages, :requires_node_credentials, :boolean, null: false, default: false
    add_column :file_storages, :node_mount_capable, :boolean, null: false, default: false
    add_column :file_storages, :deployment_shape, :string, null: false, default: "self_hosted"

    add_check_constraint :file_storages,
      "encryption_mode IN ('none', 'fscrypt', 'luks', 'client_side_aes')",
      name: "file_storages_encryption_mode_check"

    add_check_constraint :file_storages,
      "deployment_shape IN ('self_hosted', 'gateway_proxy')",
      name: "file_storages_deployment_shape_check"

    add_index :file_storages, :node_mount_capable,
      where: "node_mount_capable = true",
      name: "index_file_storages_node_mount_capable_true"
  end
end
