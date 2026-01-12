# frozen_string_literal: true

class FileVersion < ApplicationRecord
  # Authentication & Authorization

  # Concerns
  include Auditable

  # Associations
  belongs_to :file_object
  belongs_to :account
  belongs_to :created_by, class_name: "User", foreign_key: "created_by_id"

  # Validations
  validates :version_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :version_number, uniqueness: { scope: :file_object_id }
  validates :storage_key, presence: true
  validates :file_size, presence: true, numericality: { greater_than: 0 }

  # JSON columns
  attribute :change_metadata, :json, default: -> { {} }
  attribute :metadata, :json, default: -> { {} }

  # Scopes
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :recent, -> { order(version_number: :desc) }
  scope :oldest, -> { order(version_number: :asc) }
  scope :by_creator, ->(user_id) { where(created_by_id: user_id) }

  # Methods
  def deleted?
    deleted_at.present?
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def restore!
    update!(deleted_at: nil)
  end

  def human_file_size
    return "0 B" if file_size.zero?

    units = %w[B KB MB GB TB]
    exp = (Math.log(file_size) / Math.log(1024)).to_i
    exp = [ exp, units.size - 1 ].min

    format("%.2f %s", file_size.to_f / (1024**exp), units[exp])
  end

  def version_summary
    {
      version_number: version_number,
      storage_key: storage_key,
      file_size: file_size,
      human_file_size: human_file_size,
      checksum_sha256: checksum_sha256,
      change_description: change_description,
      created_by: created_by.display_name,
      created_at: created_at.iso8601
    }
  end
end
