# frozen_string_literal: true

module StorageProviders
  # The filesystem type under a path, from /proc/self/mountinfo by
  # longest-prefix mount point (IMP-d97f6e3bbc2b, round 5). The NFS and SMB
  # providers consult it in initialize_storage so the liveness marker is
  # written only onto a base that really sits on a share of the right type —
  # never onto the unmounted mount point beneath it, which the legacy
  # `mounted?` (a substring test over `mount` output, trivially true for a
  # mount_path-only configuration) could not tell apart.
  #
  # `read` is the one seam specs inject; `fstype_for` also takes the table
  # as `source:` for pure tests. A path under no mount, a blank path or an
  # unreadable table all answer nil, which callers treat as "not on the
  # expected share" — fail closed.
  module MountInfo
    PATH = "/proc/self/mountinfo"

    def self.read
      File.read(PATH)
    end

    def self.fstype_for(path, source: nil)
      return nil if path.blank?

      best = nil
      (source || read).each_line do |line|
        # id parent major:minor root MOUNT_POINT options [optional...] - FSTYPE source superopts
        before, separator, after = line.partition(" - ")
        next if separator.empty?

        fields = before.split
        next if fields.size < 5

        mount_point = unescape(fields[4])
        next unless under?(path, mount_point)

        fstype = after.split.first
        next if fstype.blank?

        best = [ mount_point, fstype ] if best.nil? || mount_point.length > best[0].length
      end
      best&.last
    rescue SystemCallError, IOError
      nil
    end

    # mountinfo escapes space, tab, newline and backslash as \040, \011,
    # \012 and \134.
    def self.unescape(value)
      value.gsub(/\\([0-7]{3})/) { Regexp.last_match(1).to_i(8).chr }
    end

    def self.under?(path, mount_point)
      return true if path == mount_point

      prefix = mount_point.end_with?("/") ? mount_point : "#{mount_point}/"
      path.start_with?(prefix)
    end
    private_class_method :unescape, :under?
  end
end
