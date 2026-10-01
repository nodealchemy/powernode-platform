# frozen_string_literal: true

module StorageProviders
  # Positive liveness evidence for a path-backed store (local root, NFS or
  # SMB mount) — IMP-d97f6e3bbc2b, round 4. A GDPR erasure counts a MISSING
  # blob as "already removed" only with evidence that the store it should be
  # on is actually there; with no evidence the blob is refused and the row
  # stays. The evidence is a marker file (Base::LIVENESS_MARKER) at the
  # store's base, written by initialize_storage — i.e. by a successful write
  # to the store — holding a nonce that is also kept on the
  # FileManagement::Storage row. The marker must be readable AND carry the
  # row's current nonce.
  #
  # Why this and not a mount-table or device test: an unmounted mount point
  # (an ordinary empty directory), an empty bind mount, an autofs map whose
  # server is down (the lookup triggers an automount that fails), an
  # unmounted dedicated local volume and an unmounted subvolume all lack
  # the marker; a store whose mount_path is NESTED under the real mount has
  # it, because initialize_storage wrote it there. The nonce defeats the one
  # trap a bare marker has: initialize_storage run while the share was
  # unmounted leaves a marker on the underlying disk that is shadowed once
  # the share mounts and visible again when it unmounts — a later
  # initialize on the live share writes a NEW nonce, so the shadowed copy no
  # longer matches. The residue that remains: if the LAST initialize ran
  # unmounted and nothing re-initialized since, the unmounted state matches.
  #
  # Stores created before this marker existed have no nonce on their row
  # and therefore no evidence: their missing blobs are refused until an
  # operator re-runs initialize_storage (Admin → Storage → test/initialize),
  # which writes the marker with the share mounted.
  module PathLiveness
    def store_live?
      nonce = liveness_nonce
      return false if nonce.blank?

      File.read(liveness_marker_path).strip == nonce
    rescue SystemCallError, IOError
      false
    end

    # A fresh nonce, written to the store and kept on the row. Called only
    # from initialize_storage, after the store's layout was created there.
    def write_liveness_marker!
      nonce = SecureRandom.hex(16)
      File.write(liveness_marker_path, nonce)
      metadata = @storage_config.metadata.to_h.merge("liveness_marker" => nonce)
      if @storage_config.persisted?
        @storage_config.update_columns(metadata: metadata)
      else
        @storage_config.metadata = metadata
      end
      nonce
    end

    private

    def liveness_nonce
      @storage_config.metadata.to_h["liveness_marker"].to_s
    end

    def liveness_marker_path
      File.join(liveness_base.to_s, StorageProviders::Base::LIVENESS_MARKER)
    end
  end
end
