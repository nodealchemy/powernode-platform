# frozen_string_literal: true

module FileManagement
  class Share < ApplicationRecord
    include Auditable

    # Associations
    belongs_to :object, class_name: "FileManagement::Object", foreign_key: :file_object_id
    belongs_to :account
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id"

    # Validations
    validates :share_token, presence: true, uniqueness: true
    validates :share_type, presence: true, inclusion: {
      in: %w[public_link email user api],
      message: "must be a valid share type"
    }
    validates :access_level, presence: true, inclusion: {
      in: %w[view download edit admin],
      message: "must be a valid access level"
    }
    validates :status, presence: true, inclusion: {
      in: %w[active expired revoked pending],
      message: "must be a valid status"
    }
    validates :max_downloads, numericality: { only_integer: true, greater_than: 0, allow_nil: true }
    validates :download_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :validate_max_downloads_not_exceeded
    validate :validate_not_expired

    # JSON columns
    attribute :recipients, :json, default: -> { [] }
    attribute :access_log, :json, default: -> { [] }
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :active, -> { where(status: "active").where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :expired, -> { where(status: "expired").or(where("expires_at IS NOT NULL AND expires_at <= ?", Time.current)) }
    scope :revoked, -> { where(status: "revoked") }
    scope :public_links, -> { where(share_type: "public_link") }
    scope :email_shares, -> { where(share_type: "email") }
    scope :user_shares, -> { where(share_type: "user") }
    scope :api_shares, -> { where(share_type: "api") }
    scope :recent, -> { order(created_at: :desc) }
    scope :by_creator, ->(user_id) { where(created_by_id: user_id) }

    # Callbacks
    before_validation :generate_share_token, on: :create
    before_save :check_expiration
    after_create :send_share_notifications

    # Status methods
    def active?
      status == "active" && !expired_by_time?
    end

    def expired?
      status == "expired" || expired_by_time?
    end

    def revoked?
      status == "revoked"
    end

    def pending?
      status == "pending"
    end

    def expired_by_time?
      expires_at.present? && expires_at <= Time.current
    end

    # Share type methods
    def public_link?
      share_type == "public_link"
    end

    def email_share?
      share_type == "email"
    end

    def user_share?
      share_type == "user"
    end

    def api_share?
      share_type == "api"
    end

    # Access level methods
    def view_only?
      access_level == "view"
    end

    def download_allowed?
      %w[download edit admin].include?(access_level)
    end

    def edit_allowed?
      %w[edit admin].include?(access_level)
    end

    def admin_access?
      access_level == "admin"
    end

    # Download limits
    def max_downloads_enabled?
      max_downloads.present?
    end

    def downloads_remaining
      return Float::INFINITY unless max_downloads_enabled?

      [ max_downloads - download_count, 0 ].max
    end

    def downloads_exceeded?
      return false unless max_downloads_enabled?

      download_count >= max_downloads
    end

    def can_download?
      active? && !downloads_exceeded? && download_allowed?
    end

    # Record access
    def record_access!(ip_address: nil, user_agent: nil, user_id: nil)
      increment!(:download_count)
      update_column(:last_accessed_at, Time.current)

      log_entry = {
        "timestamp" => Time.current.iso8601,
        "ip_address" => ip_address,
        "user_agent" => user_agent,
        "user_id" => user_id,
        "download_number" => download_count
      }

      self.access_log = (access_log || []) + [ log_entry ]
      save
    end

    # Lifecycle management
    def revoke!(reason = nil)
      update!(
        status: "revoked",
        metadata: metadata.merge({
          "revoked_at" => Time.current.iso8601,
          "revocation_reason" => reason
        })
      )
    end

    def extend_expiration!(duration)
      new_expiration = expires_at ? [ expires_at, Time.current ].max + duration : Time.current + duration

      update!(
        expires_at: new_expiration,
        status: "active"
      )
    end

    def activate!
      return false if expired_by_time?

      update!(status: "active")
    end

    # Password protection
    def password_protected?
      password_digest.present?
    end

    def authenticate_password(password)
      return false unless password_protected?

      BCrypt::Password.new(password_digest).is_password?(password)
    end

    def set_password(password)
      require "bcrypt"
      self.password_digest = BCrypt::Password.create(password)
      save
    end

    # URL generation
    def share_url
      "#{Rails.application.config.base_url}/shared/#{share_token}"
    end

    def download_url
      "#{Rails.application.config.base_url}/shared/#{share_token}/download"
    end

    # Recipients management
    def add_recipient(email_or_user_id, name: nil)
      recipient_entry = if email_or_user_id.include?("@")
                          { "email" => email_or_user_id, "name" => name }
      else
                          { "user_id" => email_or_user_id }
      end

      self.recipients = (recipients || []) + [ recipient_entry ]
      save
    end

    def remove_recipient(email_or_user_id)
      self.recipients = recipients.reject do |r|
        r["email"] == email_or_user_id || r["user_id"] == email_or_user_id
      end
      save
    end

    # Summary
    def share_summary
      {
        id: id,
        share_token: share_token,
        share_type: share_type,
        access_level: access_level,
        status: status,
        file: object.filename,
        share_url: share_url,
        created_by: created_by.display_name,
        created_at: created_at.iso8601,
        expires_at: expires_at&.iso8601,
        download_count: download_count,
        max_downloads: max_downloads,
        downloads_remaining: max_downloads_enabled? ? downloads_remaining : "unlimited",
        password_protected: password_protected?,
        recipients_count: recipients.size,
        last_accessed_at: last_accessed_at&.iso8601
      }
    end

    private

    def generate_share_token
      self.share_token ||= SecureRandom.urlsafe_base64(32)
    end

    def check_expiration
      if expired_by_time? && status == "active"
        self.status = "expired"
      end
    end

    def validate_max_downloads_not_exceeded
      return unless download_count_changed?
      return unless max_downloads_enabled?
      return unless download_count > max_downloads

      errors.add(:base, "Maximum downloads exceeded")
    end

    def validate_not_expired
      return unless new_record? && expired_by_time?

      errors.add(:expires_at, "cannot be in the past")
    end

    def send_share_notifications
      return unless email_share? || user_share?
    end
  end
end
