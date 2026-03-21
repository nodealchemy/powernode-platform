# frozen_string_literal: true

module System
  class ProviderVolumeSnapshotSerializer
    def initialize(snapshot)
      @snapshot = snapshot
    end

    def as_json
      {
        id: @snapshot.id,
        name: @snapshot.name,
        description: @snapshot.description,
        external_id: @snapshot.external_id,
        size_gb: @snapshot.size_gb,
        status: @snapshot.status,
        encrypted: @snapshot.encrypted,
        progress: @snapshot.progress,
        config: @snapshot.config,
        volume_id: @snapshot.volume_id,
        volume_name: @snapshot.volume&.name,
        can_restore: @snapshot.can_restore?,
        can_delete: @snapshot.can_delete?,
        in_progress: @snapshot.in_progress?,
        finished: @snapshot.finished?,
        created_at: @snapshot.created_at,
        updated_at: @snapshot.updated_at
      }
    end
  end
end
