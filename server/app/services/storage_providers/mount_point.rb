# frozen_string_literal: true

module StorageProviders
  # Exact mount-point test for a path-backed store (IMP-d97f6e3bbc2b, round
  # 3). A directory is a mount point iff it sits on a different device from
  # its parent (the root filesystem is one by definition). Symlinks and
  # trailing slashes are resolved first. No shell-out, no substring match
  # over `mount` output, no server address — the things that made the
  # providers' legacy `mounted?` fail open (an fstab-managed mount with no
  # server_address, any cifs mount on the host, /mnt/nfs matching
  # /mnt/nfs2) and fail closed (a trailing slash, a symlinked mount path,
  # `mount` off the unit's PATH).
  #
  # Used by the NFS and SMB providers' delete_file to decide what a MISSING
  # blob means: on a mounted share it is already removed; on an unmounted
  # mount point — an ordinary empty directory — it is unreachable. The
  # legacy `mounted?` keeps serving initialize_storage / test_connection /
  # health_check unchanged.
  module MountPoint
    module_function

    def mount_point?(path)
      return false if path.blank?

      resolved = File.realpath(path.to_s)
      return false unless File.directory?(resolved)
      return true if resolved == "/"

      device_of(resolved) != device_of(File.dirname(resolved))
    rescue SystemCallError
      false
    end

    # The one stat seam; specs stub this rather than the predicate.
    def device_of(resolved_path)
      File.stat(resolved_path).dev
    end
  end
end
