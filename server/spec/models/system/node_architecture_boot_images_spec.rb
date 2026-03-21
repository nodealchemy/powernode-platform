# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::NodeArchitecture, 'boot image functionality', type: :model do
  let(:account) { create(:account) }

  describe 'IMAGE_FORMATS constant' do
    it 'defines valid image formats' do
      expect(System::NodeArchitecture::IMAGE_FORMATS).to eq(%w[raw qcow2 vmdk vhd ami iso])
    end
  end

  describe 'validations' do
    describe 'image_format' do
      it 'accepts valid image formats' do
        System::NodeArchitecture::IMAGE_FORMATS.each do |format|
          arch = build(:system_node_architecture, account: account, image_format: format)
          expect(arch).to be_valid
        end
      end

      it 'allows nil image_format' do
        arch = build(:system_node_architecture, account: account, image_format: nil)
        expect(arch).to be_valid
      end

      it 'rejects invalid image formats' do
        arch = build(:system_node_architecture, account: account, image_format: 'invalid')
        expect(arch).not_to be_valid
        expect(arch.errors[:image_format]).to include('is not included in the list')
      end
    end

    describe 'checksum validations' do
      let(:valid_sha256) { Digest::SHA256.hexdigest('test') }
      let(:invalid_checksum) { 'not-a-valid-sha256' }

      it 'accepts valid SHA256 kernel_checksum' do
        arch = build(:system_node_architecture, account: account, kernel_checksum: valid_sha256)
        expect(arch).to be_valid
      end

      it 'rejects invalid kernel_checksum' do
        arch = build(:system_node_architecture, account: account, kernel_checksum: invalid_checksum)
        expect(arch).not_to be_valid
        expect(arch.errors[:kernel_checksum]).to include('must be a valid SHA256 hash')
      end

      it 'accepts valid SHA256 ramdisk_checksum' do
        arch = build(:system_node_architecture, account: account, ramdisk_checksum: valid_sha256)
        expect(arch).to be_valid
      end

      it 'rejects invalid ramdisk_checksum' do
        arch = build(:system_node_architecture, account: account, ramdisk_checksum: invalid_checksum)
        expect(arch).not_to be_valid
        expect(arch.errors[:ramdisk_checksum]).to include('must be a valid SHA256 hash')
      end

      it 'accepts valid SHA256 image_checksum' do
        arch = build(:system_node_architecture, account: account, image_checksum: valid_sha256)
        expect(arch).to be_valid
      end

      it 'rejects invalid image_checksum' do
        arch = build(:system_node_architecture, account: account, image_checksum: invalid_checksum)
        expect(arch).not_to be_valid
        expect(arch.errors[:image_checksum]).to include('must be a valid SHA256 hash')
      end

      it 'allows nil checksums' do
        arch = build(:system_node_architecture, account: account,
                     kernel_checksum: nil, ramdisk_checksum: nil, image_checksum: nil)
        expect(arch).to be_valid
      end

      it 'accepts uppercase SHA256 checksums' do
        arch = build(:system_node_architecture, account: account, kernel_checksum: valid_sha256.upcase)
        expect(arch).to be_valid
      end
    end
  end

  describe '#has_kernel?' do
    let(:kernel_file) { create(:file_object) }

    it 'returns true when kernel_file_object is present' do
      arch = create(:system_node_architecture, account: account, kernel_file_object: kernel_file)
      expect(arch.has_kernel?).to be true
    end

    it 'returns false when kernel_file_object is nil' do
      arch = create(:system_node_architecture, account: account, kernel_file_object: nil)
      expect(arch.has_kernel?).to be false
    end
  end

  describe '#has_ramdisk?' do
    let(:ramdisk_file) { create(:file_object) }

    it 'returns true when ramdisk_file_object is present' do
      arch = create(:system_node_architecture, account: account, ramdisk_file_object: ramdisk_file)
      expect(arch.has_ramdisk?).to be true
    end

    it 'returns false when ramdisk_file_object is nil' do
      arch = create(:system_node_architecture, account: account, ramdisk_file_object: nil)
      expect(arch.has_ramdisk?).to be false
    end
  end

  describe '#has_image?' do
    let(:image_file) { create(:file_object) }

    it 'returns true when image_file_object is present' do
      arch = create(:system_node_architecture, account: account, image_file_object: image_file)
      expect(arch.has_image?).to be true
    end

    it 'returns false when image_file_object is nil' do
      arch = create(:system_node_architecture, account: account, image_file_object: nil)
      expect(arch.has_image?).to be false
    end
  end

  describe '#boot_ready?' do
    let(:kernel_file) { create(:file_object) }
    let(:image_file) { create(:file_object) }

    it 'returns true when both kernel and image are present' do
      arch = create(:system_node_architecture, account: account,
                    kernel_file_object: kernel_file, image_file_object: image_file)
      expect(arch.boot_ready?).to be true
    end

    it 'returns false when kernel is missing' do
      arch = create(:system_node_architecture, account: account,
                    kernel_file_object: nil, image_file_object: image_file)
      expect(arch.boot_ready?).to be false
    end

    it 'returns false when image is missing' do
      arch = create(:system_node_architecture, account: account,
                    kernel_file_object: kernel_file, image_file_object: nil)
      expect(arch.boot_ready?).to be false
    end
  end

  describe '#verify_kernel_checksum' do
    let(:checksum) { Digest::SHA256.hexdigest('kernel_data') }

    it 'returns true when checksum matches' do
      arch = create(:system_node_architecture, account: account, kernel_checksum: checksum)
      expect(arch.verify_kernel_checksum(checksum)).to be true
    end

    it 'returns true when checksum matches case-insensitively' do
      arch = create(:system_node_architecture, account: account, kernel_checksum: checksum.downcase)
      expect(arch.verify_kernel_checksum(checksum.upcase)).to be true
    end

    it 'returns false when checksum does not match' do
      arch = create(:system_node_architecture, account: account, kernel_checksum: checksum)
      expect(arch.verify_kernel_checksum('different_checksum')).to be false
    end

    it 'returns true when stored checksum is blank' do
      arch = create(:system_node_architecture, account: account, kernel_checksum: nil)
      expect(arch.verify_kernel_checksum(checksum)).to be true
    end
  end

  describe '#verify_ramdisk_checksum' do
    let(:checksum) { Digest::SHA256.hexdigest('ramdisk_data') }

    it 'returns true when checksum matches' do
      arch = create(:system_node_architecture, account: account, ramdisk_checksum: checksum)
      expect(arch.verify_ramdisk_checksum(checksum)).to be true
    end

    it 'returns false when checksum does not match' do
      arch = create(:system_node_architecture, account: account, ramdisk_checksum: checksum)
      expect(arch.verify_ramdisk_checksum('wrong')).to be false
    end

    it 'returns true when stored checksum is blank' do
      arch = create(:system_node_architecture, account: account, ramdisk_checksum: nil)
      expect(arch.verify_ramdisk_checksum(checksum)).to be true
    end
  end

  describe '#verify_image_checksum' do
    let(:checksum) { Digest::SHA256.hexdigest('image_data') }

    it 'returns true when checksum matches' do
      arch = create(:system_node_architecture, account: account, image_checksum: checksum)
      expect(arch.verify_image_checksum(checksum)).to be true
    end

    it 'returns false when checksum does not match' do
      arch = create(:system_node_architecture, account: account, image_checksum: checksum)
      expect(arch.verify_image_checksum('wrong')).to be false
    end

    it 'returns true when stored checksum is blank' do
      arch = create(:system_node_architecture, account: account, image_checksum: nil)
      expect(arch.verify_image_checksum(checksum)).to be true
    end
  end

  describe '#boot_files_info' do
    let(:kernel_file) { create(:file_object) }
    let(:kernel_checksum) { Digest::SHA256.hexdigest('kernel') }

    it 'returns structured boot files information' do
      arch = create(:system_node_architecture, account: account,
                    kernel_file_object: kernel_file,
                    kernel_checksum: kernel_checksum,
                    kernel_version: '5.15.0',
                    image_format: 'qcow2')

      info = arch.boot_files_info

      expect(info[:kernel][:present]).to be true
      expect(info[:kernel][:checksum]).to eq(kernel_checksum)
      expect(info[:kernel][:version]).to eq('5.15.0')
      expect(info[:ramdisk][:present]).to be false
      expect(info[:image][:present]).to be false
      expect(info[:image][:format]).to eq('qcow2')
    end
  end
end
