# frozen_string_literal: true

class FileObject < ApplicationRecord
  # Authentication & Authorization

  # Concerns
  include Auditable

  # Associations
  belongs_to :account
  belongs_to :file_storage
  belongs_to :uploaded_by, class_name: 'User', foreign_key: 'uploaded_by_id'
  belongs_to :deleted_by, class_name: 'User', foreign_key: 'deleted_by_id', optional: true
  belongs_to :parent_file, class_name: 'FileObject', foreign_key: 'parent_file_id', optional: true

  # Polymorphic attachment
  belongs_to :attachable, polymorphic: true, optional: true

  # Version tracking
  has_many :file_versions, dependent: :destroy
  has_many :child_versions, class_name: 'FileObject', foreign_key: 'parent_file_id', dependent: :nullify

  # Sharing
  has_many :file_shares, dependent: :destroy
  has_many :active_shares, -> { where(status: 'active').where('expires_at IS NULL OR expires_at > ?', Time.current) }, class_name: 'FileShare'

  # Processing
  has_many :file_processing_jobs, dependent: :destroy
  has_many :pending_jobs, -> { where(status: 'pending') }, class_name: 'FileProcessingJob'

  # Tags
  has_many :file_object_tags, dependent: :destroy
  has_many :file_tags, through: :file_object_tags

  # Validations
  validates :filename, presence: true, length: { maximum: 255 }
  validates :storage_key, presence: true, uniqueness: { scope: :file_storage_id }
  validates :content_type, presence: true
  validates :file_size, presence: true, numericality: { greater_than: 0 }
  validates :file_type, inclusion: {
    in: %w[image document video audio archive code data other],
    allow_nil: true
  }
  validates :category, inclusion: {
    in: %w[user_upload workflow_output ai_generated temp system import],
    allow_nil: true
  }
  validates :visibility, presence: true, inclusion: {
    in: %w[private public shared internal]
  }
  validates :processing_status, inclusion: {
    in: %w[pending processing completed failed],
    allow_nil: true
  }
  validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate :validate_storage_has_space, on: :create
  validate :validate_file_size_limits, on: :create

  # JSON columns
  attribute :access_permissions, :json, default: -> { {} }
  attribute :processing_metadata, :json, default: -> { {} }
  attribute :metadata, :json, default: -> { {} }
  attribute :exif_data, :json, default: -> { {} }
  attribute :dimensions, :json, default: -> { {} }

  # Scopes
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :latest_versions, -> { where(is_latest_version: true) }
  scope :by_type, ->(type) { where(file_type: type) }
  scope :by_category, ->(category) { where(category: category) }
  scope :by_visibility, ->(visibility) { where(visibility: visibility) }
  scope :public_files, -> { where(visibility: 'public') }
  scope :private_files, -> { where(visibility: 'private') }
  scope :shared_files, -> { where(visibility: 'shared') }
  scope :images, -> { where(file_type: 'image') }
  scope :documents, -> { where(file_type: 'document') }
  scope :videos, -> { where(file_type: 'video') }
  scope :audio_files, -> { where(file_type: 'audio') }
  scope :archives, -> { where(file_type: 'archive') }
  scope :uploaded_by_user, ->(user_id) { where(uploaded_by_id: user_id) }
  scope :attached_to, ->(attachable_type, attachable_id) { where(attachable_type: attachable_type, attachable_id: attachable_id) }
  scope :processing_completed, -> { where(processing_status: 'completed') }
  scope :processing_failed, -> { where(processing_status: 'failed') }
  scope :pending_processing, -> { where(processing_status: 'pending') }
  scope :not_expired, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :expired, -> { where.not(expires_at: nil).where('expires_at <= ?', Time.current) }
  scope :recent, -> { order(created_at: :desc) }
  scope :oldest, -> { order(created_at: :asc) }
  scope :largest_first, -> { order(file_size: :desc) }
  scope :smallest_first, -> { order(file_size: :asc) }
  scope :with_tags, -> { joins(:file_tags).distinct }
  scope :tagged_with, ->(tag_names) { joins(:file_tags).where(file_tags: { name: tag_names }).distinct }

  # Callbacks
  before_validation :set_defaults, on: :create
  before_validation :detect_file_type
  before_create :generate_storage_key
  before_create :generate_checksums
  after_create :update_storage_usage
  after_create :queue_processing_jobs
  after_destroy :remove_from_storage
  after_destroy :update_storage_usage_on_delete
  before_destroy :check_if_deletable

  # Soft delete
  def soft_delete!(deleted_by_user)
    update!(
      deleted_at: Time.current,
      deleted_by: deleted_by_user,
      metadata: metadata.merge('deleted_reason' => 'user_action')
    )
  end

  def restore!
    update!(deleted_at: nil, deleted_by: nil)
  end

  def deleted?
    deleted_at.present?
  end

  # File type detection
  def image?
    file_type == 'image' || content_type.start_with?('image/')
  end

  def document?
    file_type == 'document'
  end

  def video?
    file_type == 'video' || content_type.start_with?('video/')
  end

  def audio?
    file_type == 'audio' || content_type.start_with?('audio/')
  end

  def archive?
    file_type == 'archive'
  end

  # Visibility methods
  def public?
    visibility == 'public'
  end

  def private?
    visibility == 'private'
  end

  def shared?
    visibility == 'shared'
  end

  def internal?
    visibility == 'internal'
  end

  # Processing status
  def processing_pending?
    processing_status == 'pending'
  end

  def processing?
    processing_status == 'processing'
  end

  def processing_completed?
    processing_status == 'completed'
  end

  def processing_failed?
    processing_status == 'failed'
  end

  # Category methods
  def user_upload?
    category == 'user_upload'
  end

  def workflow_output?
    category == 'workflow_output'
  end

  def ai_generated?
    category == 'ai_generated'
  end

  def temp_file?
    category == 'temp'
  end

  # Access control
  def viewable_by?(user)
    return true if public?
    return true if uploaded_by_id == user.id
    return true if user.has_permission?('files.view_all')

    # Check permissions in access_permissions
    access_permissions.dig('viewers', user.id.to_s) == true
  end

  def downloadable_by?(user)
    return true if public?
    return true if uploaded_by_id == user.id
    return true if user.has_permission?('files.download_all')

    access_permissions.dig('downloaders', user.id.to_s) == true
  end

  def editable_by?(user)
    return true if uploaded_by_id == user.id
    return true if user.has_permission?('files.edit_all')

    access_permissions.dig('editors', user.id.to_s) == true
  end

  def deletable_by?(user)
    return true if uploaded_by_id == user.id
    return true if user.has_permission?('files.delete_all')

    access_permissions.dig('deleters', user.id.to_s) == true
  end

  # Grant access
  def grant_access(user_id, permission_type)
    permission_types = %w[viewer downloader editor deleter]
    return false unless permission_types.include?(permission_type.to_s)

    key = "#{permission_type}s"
    self.access_permissions = access_permissions.merge(
      key => (access_permissions[key] || {}).merge(user_id.to_s => true)
    )
    save
  end

  def revoke_access(user_id, permission_type)
    key = "#{permission_type}s"
    return false unless access_permissions[key]

    access_permissions[key].delete(user_id.to_s)
    save
  end

  # File operations
  def url
    file_storage.storage_provider.file_url(self)
  end

  def download_url(expires_in: 1.hour)
    file_storage.storage_provider.download_url(self, expires_in: expires_in)
  end

  def signed_url(expires_in: 1.hour, disposition: 'inline')
    file_storage.storage_provider.signed_url(self, expires_in: expires_in, disposition: disposition)
  end

  def read
    file_storage.storage_provider.read_file(self)
  end

  def stream(&block)
    file_storage.storage_provider.stream_file(self, &block)
  end

  def exists?
    file_storage.storage_provider.file_exists?(self)
  end

  # Version control
  def create_new_version!(uploaded_file, created_by_user, change_description: nil)
    new_version = self.class.create!(
      account: account,
      file_storage: file_storage,
      uploaded_by: created_by_user,
      filename: filename,
      content_type: content_type,
      category: category,
      visibility: visibility,
      attachable: attachable,
      version: version + 1,
      parent_file: self,
      is_latest_version: true,
      metadata: metadata.merge('change_description' => change_description)
    )

    # Mark this version as not latest
    update!(is_latest_version: false)

    # Create version history record
    FileVersion.create!(
      file_object: new_version,
      account: account,
      created_by: created_by_user,
      version_number: new_version.version,
      storage_key: new_version.storage_key,
      file_size: new_version.file_size,
      checksum_sha256: new_version.checksum_sha256,
      change_description: change_description
    )

    new_version
  end

  def version_history
    file_versions.order(version_number: :desc)
  end

  def revert_to_version!(version_number)
    target_version = file_versions.find_by(version_number: version_number)
    return false unless target_version

    # Copy the old version's storage key to current
    # Implementation depends on storage provider capabilities
    file_storage.storage_provider.copy_file(target_version.storage_key, storage_key)

    update!(
      file_size: target_version.file_size,
      checksum_sha256: target_version.checksum_sha256,
      version: version + 1,
      metadata: metadata.merge('reverted_from_version' => version_number)
    )
  end

  # Metadata and dimensions
  def width
    dimensions['width']
  end

  def height
    dimensions['height']
  end

  def duration
    dimensions['duration']  # For video/audio
  end

  def aspect_ratio
    return nil unless width && height

    (width.to_f / height).round(2)
  end

  # File size formatting
  def human_file_size
    return '0 B' if file_size.zero?

    units = %w[B KB MB GB TB]
    exp = (Math.log(file_size) / Math.log(1024)).to_i
    exp = [exp, units.size - 1].min

    format('%.2f %s', file_size.to_f / (1024**exp), units[exp])
  end

  # File extension
  def extension
    File.extname(filename).downcase.delete('.')
  end

  def mime_type
    content_type
  end

  # Download tracking
  def record_download!
    increment!(:download_count)
    update_column(:last_accessed_at, Time.current)
  end

  # Expiration
  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def expire_in(duration)
    update!(expires_at: duration.from_now)
  end

  # Tags
  def tag_list
    file_tags.pluck(:name)
  end

  def tag_list=(names)
    tag_names = names.is_a?(String) ? names.split(',').map(&:strip) : names

    new_tags = tag_names.map do |name|
      account.file_tags.find_or_create_by!(name: name.strip.downcase)
    end

    self.file_tags = new_tags
  end

  # Processing
  def queue_processing_job(job_type, parameters = {})
    job = file_processing_jobs.create!(
      account: account,
      job_type: job_type,
      job_parameters: parameters,
      status: 'pending'
    )

    # Queue job via worker API
    begin
      worker_client = WorkerApiClient.new
      worker_client.queue_file_processing_job(job.id, job_type)
      Rails.logger.info "[FileObject] Queued #{job_type} job for file #{id} (job: #{job.id})"
    rescue WorkerApiClient::ApiError => e
      Rails.logger.error "[FileObject] Failed to queue job: #{e.message}"
      # Mark job as failed
      job.update(status: 'failed', error_details: { error: e.message })
    end

    job
  end

  def mark_processing!
    update!(processing_status: 'processing')
  end

  def mark_processing_completed!(result_data = {})
    update!(
      processing_status: 'completed',
      processing_metadata: processing_metadata.merge(result_data)
    )
  end

  def mark_processing_failed!(error_message)
    update!(
      processing_status: 'failed',
      processing_metadata: processing_metadata.merge(
        'error' => error_message,
        'failed_at' => Time.current.iso8601
      )
    )
  end

  # Sharing
  def create_share(created_by:, share_type:, **options)
    file_shares.create!(
      account: account,
      created_by: created_by,
      share_type: share_type,
      share_token: SecureRandom.urlsafe_base64(32),
      **options
    )
  end

  def public_share_url
    return nil unless shared? || public?

    # Generate public share URL based on active share
    active_share = active_shares.where(share_type: 'public_link').first
    return nil unless active_share

    "#{Rails.application.config.base_url}/shared/#{active_share.share_token}"
  end

  # Summary
  def file_summary
    {
      id: id,
      filename: filename,
      content_type: content_type,
      file_type: file_type,
      file_size: file_size,
      human_file_size: human_file_size,
      category: category,
      visibility: visibility,
      version: version,
      is_latest_version: is_latest_version,
      uploaded_by: uploaded_by ? {
        id: uploaded_by.id,
        name: uploaded_by.name,
        email: uploaded_by.email
      } : nil,
      created_at: created_at.iso8601,
      updated_at: updated_at.iso8601,
      download_count: download_count,
      processing_status: processing_status,
      tags: tag_list,
      url: url,
      dimensions: dimensions,
      checksum_sha256: checksum_sha256
    }
  end

  private

  def set_defaults
    self.visibility ||= 'private'
    self.category ||= 'user_upload'
    self.version ||= 1
    self.is_latest_version = true if is_latest_version.nil?
    self.processing_status ||= 'pending'
    self.download_count ||= 0
    self.access_permissions ||= {}
    self.processing_metadata ||= {}
    self.metadata ||= {}
    self.exif_data ||= {}
    self.dimensions ||= {}
  end

  def detect_file_type
    return if file_type.present?

    self.file_type = case content_type
                     when /^image\//
                       'image'
                     when /^video\//
                       'video'
                     when /^audio\//
                       'audio'
                     when 'application/pdf', /word/, /excel/, /powerpoint/, /text\//
                       'document'
                     when /zip|tar|gz|rar|7z/
                       'archive'
                     when /json|xml|javascript|x-ruby|x-python/
                       'code'
                     when /csv|sql/
                       'data'
                     else
                       'other'
                     end
  end

  def generate_storage_key
    return if storage_key.present?

    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    random = SecureRandom.hex(8)
    safe_filename = filename.gsub(/[^0-9A-Za-z.\-]/, '_')

    self.storage_key = "#{category}/#{timestamp}_#{random}_#{safe_filename}"
  end

  def generate_checksums
    # Checksums will be generated during actual file upload
    # This is just a placeholder
    self.checksum_md5 ||= nil
    self.checksum_sha256 ||= nil
  end

  def validate_storage_has_space
    return unless file_storage && file_size

    unless file_storage.has_space_for?(file_size)
      errors.add(:base, 'Storage quota exceeded')
    end
  end

  def validate_file_size_limits
    max_file_size = 5.gigabytes  # Configurable per account

    if file_size > max_file_size
      errors.add(:file_size, "cannot exceed #{ActiveSupport::NumberHelper.number_to_human_size(max_file_size)}")
    end
  end

  def update_storage_usage
    file_storage.add_file_size(file_size)
  end

  def update_storage_usage_on_delete
    file_storage.remove_file_size(file_size) if file_storage
  end

  def queue_processing_jobs
    return if temp_file?

    # Queue automatic processing based on file type
    if image?
      queue_processing_job('thumbnail', { sizes: ['small', 'medium', 'large'] })
      queue_processing_job('metadata_extract')
    elsif document?
      queue_processing_job('metadata_extract')
    elsif video?
      queue_processing_job('video_processing')
    elsif audio?
      queue_processing_job('audio_processing')
    else
      # Files that don't require processing (code, archives, etc.) are immediately completed
      update_column(:processing_status, 'completed')
    end
  end

  def remove_from_storage
    file_storage.storage_provider.delete_file(self)
  rescue StandardError => e
    Rails.logger.error "Failed to delete file from storage: #{e.message}"
  end

  def check_if_deletable
    # Prevent deletion if file has active shares
    if active_shares.exists?
      errors.add(:base, 'Cannot delete file with active shares')
      throw :abort
    end
  end
end
