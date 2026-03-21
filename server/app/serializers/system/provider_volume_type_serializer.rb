# frozen_string_literal: true

module System
  class ProviderVolumeTypeSerializer
    def initialize(volume_type)
      @volume_type = volume_type
    end

    def as_json
      {
        id: @volume_type.id,
        name: @volume_type.name,
        description: @volume_type.description,
        volume_type: @volume_type.volume_type,
        min_size_gb: @volume_type.min_size_gb,
        max_size_gb: @volume_type.max_size_gb,
        min_iops: @volume_type.min_iops,
        max_iops: @volume_type.max_iops,
        min_throughput: @volume_type.min_throughput,
        max_throughput: @volume_type.max_throughput,
        enabled: @volume_type.enabled,
        specs: @volume_type.specs,
        provider_id: @volume_type.provider_id,
        provider_name: @volume_type.provider&.name,
        ssd: @volume_type.ssd?,
        hdd: @volume_type.hdd?,
        provisioned_iops: @volume_type.provisioned_iops?,
        volumes_count: @volume_type.volumes.count,
        created_at: @volume_type.created_at,
        updated_at: @volume_type.updated_at
      }
    end
  end
end
