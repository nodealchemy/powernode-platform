# frozen_string_literal: true

module System
  class NodeArchitecture < BaseRecord
    include System::Base

    # Constants
    IMAGE_FORMATS = %w[raw qcow2 vmdk vhd ami iso].freeze

    # Associations
    belongs_to :account
    has_many :node_platforms, class_name: 'System::NodePlatform', dependent: :restrict_with_error

    # File attachments via FileObject
    belongs_to :kernel_file_object, class_name: 'FileObject', optional: true
    belongs_to :ramdisk_file_object, class_name: 'FileObject', optional: true
    belongs_to :image_file_object, class_name: 'FileObject', optional: true

    # Validations
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :image_format, inclusion: { in: IMAGE_FORMATS }, allow_nil: true
    validates :kernel_checksum, format: { with: /\A[a-f0-9]{64}\z/i, message: 'must be a valid SHA256 hash' }, allow_nil: true
    validates :ramdisk_checksum, format: { with: /\A[a-f0-9]{64}\z/i, message: 'must be a valid SHA256 hash' }, allow_nil: true
    validates :image_checksum, format: { with: /\A[a-f0-9]{64}\z/i, message: 'must be a valid SHA256 hash' }, allow_nil: true

    # === Boot Image Methods ===
    def has_kernel?
      kernel_file_object.present?
    end

    def has_ramdisk?
      ramdisk_file_object.present?
    end

    def has_image?
      image_file_object.present?
    end

    def boot_ready?
      has_kernel? && has_image?
    end

    def verify_kernel_checksum(file_checksum)
      return true if kernel_checksum.blank?
      kernel_checksum.downcase == file_checksum.to_s.downcase
    end

    def verify_ramdisk_checksum(file_checksum)
      return true if ramdisk_checksum.blank?
      ramdisk_checksum.downcase == file_checksum.to_s.downcase
    end

    def verify_image_checksum(file_checksum)
      return true if image_checksum.blank?
      image_checksum.downcase == file_checksum.to_s.downcase
    end

    def boot_files_info
      {
        kernel: {
          present: has_kernel?,
          checksum: kernel_checksum,
          version: kernel_version
        },
        ramdisk: {
          present: has_ramdisk?,
          checksum: ramdisk_checksum
        },
        image: {
          present: has_image?,
          checksum: image_checksum,
          format: image_format
        }
      }
    end
  end
end
