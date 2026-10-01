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
  # trap a bare marker has: a marker left on the underlying disk is
  # shadowed once the share mounts and visible again when it unmounts — a
  # later initialize on the live share writes a NEW nonce, so the shadowed
  # copy no longer matches. The NFS and SMB providers also refuse to
  # initialize at all unless the base sits on a mount of their filesystem
  # type (StorageProviders::MountInfo), so such a marker is not written in
  # the first place.
  #
  # Liveness is three-valued (round 5):
  #   :unknown — the row has no nonce: the store was never initialized with
  #              the marker (it predates it). No evidence either way, so a
  #              missing blob is refused with its own reason
  #              (store_not_initialized) but the store is NOT treated as
  #              dead — its other files, whose blobs may well exist, are
  #              still attempted. The fix is to re-run initialize_storage
  #              (Admin → Storage → test/initialize) with the share mounted.
  #   :live    — the marker is readable and carries the row's nonce.
  #   :dead    — the row has a nonce but the marker is unreadable or
  #              mismatched: the store is not where it should be.
  module PathLiveness
    # Why the last delete_file refused a MISSING blob, or nil: carried into
    # FileManagement::Object::StorageRemovalFailed so the erasure's failure
    # reason, the deletion request's error_message and the termination log
    # can say what to do about it.
    attr_reader :last_removal_refusal

    def store_liveness
      nonce = liveness_nonce
      return :unknown if nonce.blank?

      File.read(liveness_marker_path).strip == nonce ? :live : :dead
    rescue SystemCallError, IOError
      :dead
    end

    # The erasure's dead-store probe: only :dead short-circuits a storage's
    # remaining files. :unknown stays per-file.
    def store_live?
      store_liveness != :dead
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

    # For delete_file when the blob is MISSING: "already removed" only on
    # :live evidence. Records the refusal reason for the model to carry.
    def missing_blob_removed?(file_object, store_name)
      case store_liveness
      when :live
        true
      when :unknown
        @last_removal_refusal = "store_not_initialized"
        log_error("Refusing to report file object #{file_object.id} removed: the #{store_name} store has no liveness marker " \
                  "— initialize it (Admin → Storage) with its share mounted")
        false
      else
        log_error("Refusing to report file object #{file_object.id} removed: no liveness evidence for the #{store_name} store")
        false
      end
    end

    # The filesystem type under the store's base (symlinks resolved), or nil
    # when the base or the mount table cannot be read.
    def base_fstype
      StorageProviders::MountInfo.fstype_for(File.realpath(liveness_base.to_s))
    rescue SystemCallError
      nil
    end

    def liveness_nonce
      @storage_config.metadata.to_h["liveness_marker"].to_s
    end

    def liveness_marker_path
      File.join(liveness_base.to_s, StorageProviders::Base::LIVENESS_MARKER)
    end
  end
end
