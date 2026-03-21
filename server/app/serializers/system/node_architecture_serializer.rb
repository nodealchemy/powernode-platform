# frozen_string_literal: true

module System
  class NodeArchitectureSerializer
    def initialize(architecture)
      @architecture = architecture
    end

    def as_json
      {
        id: @architecture.id,
        name: @architecture.name,
        description: @architecture.description,
        kernel_options: @architecture.kernel_options,
        enabled: @architecture.enabled,
        public: @architecture.public,
        kernel_file_object_id: @architecture.kernel_file_object_id,
        ramdisk_file_object_id: @architecture.ramdisk_file_object_id,
        image_file_object_id: @architecture.image_file_object_id,
        platforms_count: @architecture.node_platforms.count,
        created_at: @architecture.created_at,
        updated_at: @architecture.updated_at
      }
    end
  end
end
