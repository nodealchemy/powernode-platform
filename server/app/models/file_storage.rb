# frozen_string_literal: true

class FileStorage < ApplicationRecord
  # Authentication & Authorization


  # Concerns
  include Auditable

  # Associations
  belongs_to :account
  has_many :file_objects, dependent: :restrict_with_error
  has_many :file_versions, through: :file_objects

  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :name, uniqueness: { scope: :account_id, case_sensitive: false }
  validates :provider_type, presence: true, inclusion: {
    in: %w[local s3 gcs azure ftp webdav custom],
    message: "must be a valid provider type"
  }
  validates :status, presence: true, inclusion: {
    in: %w[active inactive maintenance failed],
    message: "must be a valid status"
  }
  validates :priority, presence: true, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 1000
  }
  validates :files_count, numericality: { greater_than_or_equal_to: 0 }
  validates :total_size_bytes, numericality: { greater_than_or_equal_to: 0 }
  validates :quota_bytes, numericality: { greater_than: 0, allow_nil: true }
  validate :validate_configuration
  validate :validate_quota_not_exceeded, if: :quota_bytes?

  # JSON columns with default values
  attribute :configuration, :json, default: -> { {} }
  attribute :capabilities, :json, default: -> { {} }
  attribute :metadata, :json, default: -> { {} }
  attribute :health_details, :json, default: -> { {} }

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :inactive, -> { where(status: "inactive") }
  scope :default, -> { where(is_default: true) }
  scope :healthy, -> { where(health_status: "healthy") }
  scope :degraded, -> { where(health_status: "degraded") }
  scope :failed, -> { where(health_status: "failed") }
  scope :by_priority, -> { order(:priority, :created_at) }
  scope :by_type, ->(type) { where(provider_type: type) }
  scope :available, -> { active.where("quota_bytes IS NULL OR total_size_bytes < quota_bytes") }
  scope :with_space, -> { active.where("quota_bytes IS NULL OR (quota_bytes - total_size_bytes) > ?", 100.megabytes) }

  # Callbacks
  before_validation :set_defaults, on: :create
  before_validation :normalize_name
  before_save :encrypt_sensitive_configuration
  after_create :initialize_storage_backend
  after_update :sync_provider_changes, if: :saved_change_to_configuration?

  # Status methods
  def active?
    status == "active"
  end

  def inactive?
    status == "inactive"
  end

  def maintenance_mode?
    status == "maintenance"
  end

  def failed?
    status == "failed"
  end

  # Health methods
  def healthy?
    health_status == "healthy"
  end

  def degraded?
    health_status == "degraded"
  end

  def health_failed?
    health_status == "failed"
  end

  # Provider type methods
  def local?
    provider_type == "local"
  end

  def s3?
    provider_type == "s3"
  end

  def gcs?
    provider_type == "gcs"
  end

  def azure?
    provider_type == "azure"
  end

  def cloud?
    %w[s3 gcs azure].include?(provider_type)
  end

  # Quota and storage methods
  def quota_enabled?
    quota_bytes.present?
  end

  def quota_percentage_used
    return 0 unless quota_enabled?
    return 0 if quota_bytes.zero?

    ((total_size_bytes.to_f / quota_bytes) * 100).round(2)
  end

  def available_space_bytes
    return Float::INFINITY unless quota_enabled?

    [ quota_bytes - total_size_bytes, 0 ].max
  end

  def available_space_percentage
    return 100 unless quota_enabled?

    100 - quota_percentage_used
  end

  def has_space_for?(size_bytes)
    return true unless quota_enabled?

    available_space_bytes >= size_bytes
  end

  def quota_exceeded?
    return false unless quota_enabled?

    total_size_bytes >= quota_bytes
  end

  def near_quota_limit?(threshold_percentage = 80)
    return false unless quota_enabled?

    quota_percentage_used >= threshold_percentage
  end

  # Storage operations
  def add_file_size(bytes)
    increment!(:files_count)
    increment!(:total_size_bytes, bytes)
  end

  def remove_file_size(bytes)
    decrement!(:files_count)
    decrement!(:total_size_bytes, bytes)
  end

  # Health check
  def perform_health_check!
    result = storage_provider.health_check

    update!(
      health_status: result[:status],
      health_details: result[:details],
      last_health_check_at: Time.current
    )

    result[:status] == "healthy"
  rescue StandardError => e
    update!(
      health_status: "failed",
      health_details: {
        "error" => e.message,
        "error_class" => e.class.name,
        "checked_at" => Time.current.iso8601
      },
      last_health_check_at: Time.current
    )

    false
  end

  def health_check_needed?
    return true if last_health_check_at.nil?

    last_health_check_at < 5.minutes.ago
  end

  # Provider adapter
  def storage_provider
    @storage_provider ||= StorageProviderFactory.create(self)
  end

  # Configuration helpers
  def get_config(key)
    configuration[key.to_s]
  end

  def set_config(key, value)
    self.configuration = configuration.merge(key.to_s => value)
  end

  def get_capability(key)
    capabilities[key.to_s]
  end

  def supports?(capability)
    capabilities[capability.to_s] == true
  end

  # Security methods
  def blocked_extensions
    capabilities["blocked_extensions"] || default_blocked_extensions
  end

  def blocked_mime_types
    capabilities["blocked_mime_types"] || default_blocked_mime_types
  end

  # Display methods
  def display_name
    "#{name} (#{provider_type.upcase})"
  end

  def storage_summary
    {
      id: id,
      name: name,
      provider_type: provider_type,
      status: status,
      health_status: health_status,
      is_default: is_default,
      files_count: files_count,
      total_size: human_file_size(total_size_bytes),
      total_size_bytes: total_size_bytes,
      quota: quota_bytes ? human_file_size(quota_bytes) : "Unlimited",
      quota_bytes: quota_bytes,
      quota_used_percentage: quota_percentage_used,
      available_space: quota_bytes ? human_file_size(available_space_bytes) : "Unlimited",
      priority: priority,
      last_health_check: last_health_check_at&.iso8601,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end

  # Activate/deactivate
  def activate!
    return true if active?

    if perform_health_check!
      update!(status: "active")
      true
    else
      errors.add(:base, "Cannot activate storage with failed health check")
      false
    end
  end

  def deactivate!
    return true if inactive?

    update!(status: "inactive")
  end

  def maintenance_mode!
    update!(status: "maintenance")
  end

  # Test connection
  def test_connection
    storage_provider.test_connection
  rescue StandardError => e
    {
      success: false,
      error: e.message,
      error_class: e.class.name
    }
  end

  private

  def set_defaults
    self.status ||= "active"
    self.priority ||= 100
    self.configuration ||= {}
    self.capabilities ||= default_capabilities_for_provider
    self.metadata ||= {}
    self.health_details ||= {}
    self.files_count ||= 0
    self.total_size_bytes ||= 0
  end

  def normalize_name
    self.name = name.strip if name.present?
  end

  def validate_configuration
    return if configuration.blank?

    case provider_type
    when "local"
      validate_local_configuration
    when "s3"
      validate_s3_configuration
    when "gcs"
      validate_gcs_configuration
    when "azure"
      validate_azure_configuration
    end
  end

  def validate_local_configuration
    unless configuration["root_path"].present?
      errors.add(:configuration, "must include root_path for local storage")
    end
  end

  def validate_s3_configuration
    required_keys = %w[bucket region]
    missing_keys = required_keys - configuration.keys

    if missing_keys.any?
      errors.add(:configuration, "missing required keys for S3: #{missing_keys.join(', ')}")
    end
  end

  def validate_gcs_configuration
    unless configuration["bucket"].present?
      errors.add(:configuration, "must include bucket for GCS storage")
    end
  end

  def validate_azure_configuration
    required_keys = %w[container storage_account_name]
    missing_keys = required_keys - configuration.keys

    if missing_keys.any?
      errors.add(:configuration, "missing required keys for Azure: #{missing_keys.join(', ')}")
    end
  end

  def validate_quota_not_exceeded
    return unless quota_bytes.present? && total_size_bytes > quota_bytes

    errors.add(:quota_bytes, "quota has been exceeded")
  end

  def encrypt_sensitive_configuration
    # Encrypt sensitive credentials before saving
    return unless configuration_changed? && configuration.present?

    sensitive_keys = %w[access_key_id secret_access_key credentials_json storage_access_key password api_key]

    sensitive_keys.each do |key|
      next unless configuration[key].present? && !configuration[key].start_with?("encrypted:")

      configuration[key] = encrypt_value(configuration[key])
    end
  end

  def encrypt_value(value)
    # Use Rails encrypted credentials or custom encryption
    encryptor = AiCredentialEncryptionService.new
    "encrypted:#{encryptor.encrypt(value)}"
  end

  def decrypt_value(value)
    return value unless value.to_s.start_with?("encrypted:")

    encryptor = AiCredentialEncryptionService.new
    encrypted_value = value.to_s.sub("encrypted:", "")
    encryptor.decrypt(encrypted_value)
  end

  def initialize_storage_backend
    # Create initial directories or setup for local storage
    return unless local? && active?

    storage_provider.initialize_storage
  rescue StandardError => e
    Rails.logger.error "Failed to initialize storage backend: #{e.message}"
  end

  def sync_provider_changes
    # Clear cached provider when configuration changes
    @storage_provider = nil
  end

  def default_capabilities_for_provider
    case provider_type
    when "local"
      {
        "multipart_upload" => false,
        "resumable_upload" => false,
        "direct_upload" => false,
        "cdn" => false,
        "versioning" => true,
        "encryption" => false,
        "access_control" => true,
        "signed_urls" => false,
        "streaming" => true
      }
    when "s3"
      {
        "multipart_upload" => true,
        "resumable_upload" => true,
        "direct_upload" => true,
        "cdn" => true,
        "versioning" => true,
        "encryption" => true,
        "access_control" => true,
        "signed_urls" => true,
        "streaming" => true
      }
    when "gcs"
      {
        "multipart_upload" => true,
        "resumable_upload" => true,
        "direct_upload" => true,
        "cdn" => true,
        "versioning" => true,
        "encryption" => true,
        "access_control" => true,
        "signed_urls" => true,
        "streaming" => true
      }
    when "azure"
      {
        "multipart_upload" => true,
        "resumable_upload" => true,
        "direct_upload" => true,
        "cdn" => true,
        "versioning" => true,
        "encryption" => true,
        "access_control" => true,
        "signed_urls" => true,
        "streaming" => true
      }
    else
      {}
    end
  end

  def human_file_size(bytes)
    return "0 B" if bytes.zero?

    units = %w[B KB MB GB TB PB]
    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = [ exp, units.size - 1 ].min

    format("%.2f %s", bytes.to_f / (1024**exp), units[exp])
  end

  def default_blocked_extensions
    # Security-conscious defaults - block executable and potentially dangerous files
    %w[.exe .dll .bat .cmd .sh .ps1 .vbs .vbe .jse .msi .scr .pif .application .gadget .msp .com .cpl .msc .jar]
  end

  def default_blocked_mime_types
    # Block known dangerous MIME types
    %w[
      application/x-msdownload
      application/x-msdos-program
      application/x-executable
      application/x-bat
      application/x-sh
      application/vnd.microsoft.portable-executable
    ]
  end
end
