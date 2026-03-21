# frozen_string_literal: true

module System
  class ProviderVolumeSerializer
    def initialize(volume)
      @volume = volume
    end

    def as_json
      {
        id: @volume.id,
        name: @volume.name,
        description: @volume.description,
        external_id: @volume.external_id,
        size_gb: @volume.size_gb,
        iops: @volume.iops,
        throughput: @volume.throughput,
        status: @volume.status,
        device_name: @volume.device_name,
        encrypted: @volume.encrypted,
        delete_on_termination: @volume.delete_on_termination,
        config: @volume.config,
        volume_type_id: @volume.volume_type_id,
        volume_type_name: @volume.volume_type&.name,
        provider_region_id: @volume.provider_region_id,
        region_name: @volume.provider_region&.name,
        availability_zone_id: @volume.availability_zone_id,
        zone_name: @volume.availability_zone&.name,
        node_instance_id: @volume.node_instance_id,
        instance_name: @volume.node_instance&.name,
        attached: @volume.attached?,
        can_attach: @volume.can_attach?,
        can_detach: @volume.can_detach?,
        can_delete: @volume.can_delete?,
        can_snapshot: @volume.can_snapshot?,
        snapshots_count: @volume.snapshots.count,
        created_at: @volume.created_at,
        updated_at: @volume.updated_at
      }
    end
  end
end
