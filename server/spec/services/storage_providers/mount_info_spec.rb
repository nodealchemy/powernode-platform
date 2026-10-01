# frozen_string_literal: true

require 'rails_helper'

# IMP-d97f6e3bbc2b (round 5) — the filesystem type under a path, from
# /proc/self/mountinfo by longest-prefix mount point. The NFS and SMB
# providers consult it before writing the liveness marker, so a marker is
# never written onto an unmounted base. `read` is the one injectable seam.
RSpec.describe StorageProviders::MountInfo do
  let(:mountinfo) do
    <<~MI
      22 1 8:2 / / rw,relatime shared:1 - ext4 /dev/sda2 rw
      100 22 0:50 / /mnt/nfs rw,relatime shared:2 - nfs4 10.0.0.5:/export rw,vers=4.2
      101 22 0:51 / /mnt/nfs2 rw,relatime shared:3 - cifs //10.0.0.6/share rw
      102 22 0:52 / /mnt/with\\040space rw - smb3 //10.0.0.7/s rw
    MI
  end

  describe '.fstype_for' do
    it 'answers the longest-prefix mount point, not a lexical prefix' do
      expect(described_class.fstype_for('/mnt/nfs', source: mountinfo)).to eq('nfs4')
      expect(described_class.fstype_for('/mnt/nfs2', source: mountinfo)).to eq('cifs')
      expect(described_class.fstype_for('/mnt/nfs2/deeper', source: mountinfo)).to eq('cifs')
    end

    it 'answers the enclosing mount for a path nested under it' do
      expect(described_class.fstype_for('/mnt/nfs/storage-a/files', source: mountinfo)).to eq('nfs4')
    end

    it 'falls back to the root filesystem for a path under no other mount' do
      expect(described_class.fstype_for('/var/lib/powernode', source: mountinfo)).to eq('ext4')
    end

    it 'unescapes octal sequences in mount points' do
      expect(described_class.fstype_for('/mnt/with space/x', source: mountinfo)).to eq('smb3')
    end

    it 'is nil for a blank path or an unreadable table' do
      expect(described_class.fstype_for('', source: mountinfo)).to be_nil
      expect(described_class.fstype_for('/mnt/nfs', source: '')).to be_nil
      allow(described_class).to receive(:read).and_raise(Errno::ENOENT)
      expect(described_class.fstype_for('/mnt/nfs')).to be_nil
    end
  end
end
