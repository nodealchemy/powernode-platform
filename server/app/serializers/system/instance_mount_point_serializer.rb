# frozen_string_literal: true

module System
  class InstanceMountPointSerializer
    def initialize(instance_mount_point)
      @instance_mount_point = instance_mount_point
    end

    def as_json
      {
        id: @instance_mount_point.id,
        node_instance_id: @instance_mount_point.node_instance_id,
        instance_name: @instance_mount_point.instance_name,
        mount_point_id: @instance_mount_point.mount_point_id,
        mount_name: @instance_mount_point.mount_name,
        mount_path: @instance_mount_point.mount_path,
        mount_type: @instance_mount_point.mount_type,
        config: @instance_mount_point.config,
        enabled: @instance_mount_point.enabled,
        status: @instance_mount_point.status,
        created_at: @instance_mount_point.created_at,
        updated_at: @instance_mount_point.updated_at
      }
    end
  end
end
