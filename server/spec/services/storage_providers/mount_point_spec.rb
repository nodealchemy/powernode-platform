# frozen_string_literal: true

require 'rails_helper'

# IMP-d97f6e3bbc2b (round 3) — the exact mount-point test the NFS and SMB
# providers use to decide whether a MISSING blob means "already removed"
# (the share is mounted and the file is gone) or "unreachable" (the mount
# point is an empty directory). No shell-out, no substring match, no server
# address: a directory is a mount point iff its device differs from its
# parent's, after symlinks and trailing slashes are resolved. `device_of`
# is the one stat seam, so these specs never depend on the runner's mount
# table beyond the two universal facts: `/` is a mount point and a fresh
# tmp directory is not.
RSpec.describe StorageProviders::MountPoint do
  let(:dir) { Rails.root.join('tmp', "mount_point_spec_#{SecureRandom.hex(4)}") }

  before { FileUtils.mkdir_p(dir) }
  after  { FileUtils.rm_rf(dir) }

  describe '.mount_point?' do
    it 'is true for the root filesystem and false for an ordinary directory (real stat)' do
      expect(described_class.mount_point?('/')).to be true
      expect(described_class.mount_point?(dir.to_s)).to be false
    end

    it 'is true when the directory sits on a different device from its parent' do
      allow(described_class).to receive(:device_of).with(File.realpath(dir)).and_return(42)
      allow(described_class).to receive(:device_of).with(File.dirname(File.realpath(dir))).and_return(7)

      expect(described_class.mount_point?(dir.to_s)).to be true
    end

    it 'is false when the directory shares its parent device' do
      allow(described_class).to receive(:device_of).and_return(7)

      expect(described_class.mount_point?(dir.to_s)).to be false
    end

    it 'resolves a trailing slash and a symlink before testing' do
      link = Rails.root.join('tmp', "mount_point_link_#{SecureRandom.hex(4)}")
      File.symlink(dir, link)
      allow(described_class).to receive(:device_of).with(File.realpath(dir)).and_return(42)
      allow(described_class).to receive(:device_of).with(File.dirname(File.realpath(dir))).and_return(7)

      expect(described_class.mount_point?("#{dir}/")).to be true
      expect(described_class.mount_point?(link.to_s)).to be true
    ensure
      File.delete(link) if File.symlink?(link)
    end

    it 'is false for a path that does not exist, is a file, or is blank' do
      file = dir.join('f')
      File.write(file, 'x')

      expect(described_class.mount_point?(dir.join('missing').to_s)).to be false
      expect(described_class.mount_point?(file.to_s)).to be false
      expect(described_class.mount_point?(nil)).to be false
      expect(described_class.mount_point?('')).to be false
    end
  end
end
