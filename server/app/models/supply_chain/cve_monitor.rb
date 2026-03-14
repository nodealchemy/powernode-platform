# frozen_string_literal: true

module SupplyChain
  class CveMonitor < ApplicationRecord
    include Auditable
    # Note: Does not include Schedulable since schedule_cron is optional in this model

    self.table_name = "supply_chain_cve_monitors"

    # ============================================
    # Constants
    # ============================================
    SCOPE_TYPES = %w[image repository account_wide].freeze
    MIN_SEVERITIES = %w[critical high medium low].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :scope_type, presence: true, inclusion: { in: SCOPE_TYPES }
    validates :min_severity, presence: true, inclusion: { in: MIN_SEVERITIES }
    validate :scope_id_required_for_non_account_wide

    # ============================================
    # Scopes
    # ============================================
    scope :active, -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :by_scope, ->(scope_type) { where(scope_type: scope_type) }
    scope :image_scope, -> { where(scope_type: "image") }
    scope :repository_scope, -> { where(scope_type: "repository") }
    scope :account_wide, -> { where(scope_type: "account_wide") }
    scope :due_for_run, -> { active.where("next_run_at IS NULL OR next_run_at <= ?", Time.current) }
    scope :recent, -> { order(created_at: :desc) }

    # ============================================
    # Callbacks
    # ============================================
    before_save :sanitize_jsonb_fields
    before_save :calculate_next_run, if: :schedule_cron_changed?

    # ============================================
    # Instance Methods
    # ============================================
    def active?
      is_active
    end

    def image_scope?
      scope_type == "image"
    end

    def repository_scope?
      scope_type == "repository"
    end

    def account_wide?
      scope_type == "account_wide"
    end

    def due_for_run?
      active? && (next_run_at.nil? || next_run_at <= Time.current)
    end

    def severity_includes?(severity)
      severity_levels = MIN_SEVERITIES
      min_index = severity_levels.index(min_severity)
      check_index = severity_levels.index(severity&.downcase)

      return false unless min_index && check_index

      check_index <= min_index
    end

    def activate!
      update!(is_active: true)
    end

    def deactivate!
      update!(is_active: false)
    end

    def mark_run_completed!
      update!(
        last_run_at: Time.current,
        next_run_at: calculate_next_run_time
      )
    end

    def scoped_images
      case scope_type
      when "image"
        SupplyChain::ContainerImage.where(id: scope_id, account_id: account_id)
      when "repository"
        repo = Devops::Repository.find_by(id: scope_id, account_id: account_id)
        return SupplyChain::ContainerImage.none unless repo

        # Find images associated with the repository
        # This would need to be implemented based on your image-repo relationship
        SupplyChain::ContainerImage.where(account_id: account_id)
                                   .where("repository LIKE ?", "%#{repo.name}%")
      when "account_wide"
        SupplyChain::ContainerImage.where(account_id: account_id)
      else
        SupplyChain::ContainerImage.none
      end
    end

    def scoped_sboms
      case scope_type
      when "repository"
        SupplyChain::Sbom.where(repository_id: scope_id, account_id: account_id)
      when "account_wide"
        SupplyChain::Sbom.where(account_id: account_id)
      else
        SupplyChain::Sbom.none
      end
    end

    def notification_channel_count
      notification_channels&.length || 0
    end

    def alert_count
      # Returns count of alerts from metadata or defaults to 0
      metadata&.dig("alert_count") || 0
    end

    def recent_alerts(limit: 50)
      # Returns recent alerts from metadata storage
      # In a full implementation, this would query an alerts table
      (metadata&.dig("recent_alerts") || []).first(limit.to_i)
    end

    def add_notification_channel(type:, config:)
      channel = {
        type: type,
        config: config,
        added_at: Time.current.iso8601
      }

      self.notification_channels = (notification_channels || []) << channel
      save!
    end

    def remove_notification_channel(type)
      self.notification_channels = notification_channels&.reject { |c| c["type"] == type } || []
      save!
    end

    def summary
      {
        id: id,
        name: name,
        description: description,
        scope_type: scope_type,
        scope_id: scope_id,
        min_severity: min_severity,
        schedule_cron: schedule_cron,
        is_active: is_active,
        last_run_at: last_run_at,
        next_run_at: next_run_at,
        notification_channel_count: notification_channel_count,
        created_at: created_at
      }
    end

    private

    def scope_id_required_for_non_account_wide
      return if account_wide?

      errors.add(:scope_id, "is required for #{scope_type} scope") if scope_id.blank?
    end

    def sanitize_jsonb_fields
      self.notification_channels ||= []
      self.filters ||= {}
      self.metadata ||= {}
    end

    def calculate_next_run
      self.next_run_at = calculate_next_run_time
    end

    def calculate_next_run_time
      return nil unless schedule_cron.present?

      # Use a cron parser to calculate next run time
      # This is a placeholder - would use a gem like 'fugit' or 'parse-cron'
      1.hour.from_now
    end
  end
end
