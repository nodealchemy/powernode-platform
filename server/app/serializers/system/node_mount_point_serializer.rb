# frozen_string_literal: true

module System
  class NodeMountPointSerializer
    def initialize(mount_point)
      @mount_point = mount_point
    end

    def as_json
      {
        id: @mount_point.id,
        name: @mount_point.name,
        description: @mount_point.description,
        mount_path: @mount_point.mount_path,
        mount_type: @mount_point.mount_type,
        source: @mount_point.source,
        options: @mount_point.options,
        enabled: @mount_point.enabled,
        auto_mount: @mount_point.auto_mount,
        cloud_storage: @mount_point.cloud_storage?,
        network_storage: @mount_point.network_storage?,
        instances_count: @mount_point.instance_mount_points.count,
        fstab_entry: @mount_point.fstab_entry,
        created_at: @mount_point.created_at,
        updated_at: @mount_point.updated_at
      }
    end
  end
end
