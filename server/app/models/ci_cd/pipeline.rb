# frozen_string_literal: true

module CiCd
  # Pipeline definition for CI/CD workflows
  # Stores trigger configuration, steps, and execution settings
  class Pipeline < ApplicationRecord
    self.table_name = 'ci_cd_pipelines'

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true
    belongs_to :provider, class_name: "CiCd::Provider", foreign_key: :ci_cd_provider_id, optional: true
    belongs_to :ai_provider, class_name: "Ai::Provider", optional: true

    has_many :steps, class_name: "CiCd::PipelineStep", foreign_key: :ci_cd_pipeline_id, dependent: :destroy
    has_many :runs, class_name: "CiCd::PipelineRun", foreign_key: :ci_cd_pipeline_id, dependent: :destroy
    has_many :schedules, class_name: "CiCd::Schedule", foreign_key: :ci_cd_pipeline_id, dependent: :destroy
    has_many :pipeline_repositories, class_name: "CiCd::PipelineRepository", foreign_key: :ci_cd_pipeline_id, dependent: :destroy
    has_many :repositories, through: :pipeline_repositories

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true
    validates :slug, presence: true, uniqueness: { scope: :account_id },
                     format: { with: /\A[a-z0-9\-_]+\z/, message: 'only allows lowercase letters, numbers, hyphens, and underscores' }
    validates :pipeline_type, presence: true, inclusion: { in: %w[review implement security deploy custom] }
    validates :timeout_minutes, numericality: { greater_than: 0, less_than_or_equal_to: 360 }
    validates :version, numericality: { greater_than: 0 }

    validate :triggers_format
    validate :system_pipelines_immutable, on: :update

    # ============================================
    # Scopes
    # ============================================
    scope :active, -> { where(is_active: true) }
    scope :system_pipelines, -> { where(is_system: true) }
    scope :by_type, ->(type) { where(pipeline_type: type) }
    scope :concurrent_allowed, -> { where(allow_concurrent: true) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :generate_slug, on: :create

    # ============================================
    # Instance Methods
    # ============================================

    def matches_trigger?(event_type, event_data = {})
      return false unless triggers.present?

      case event_type
      when 'pull_request'
        triggers.dig('pull_request')&.include?(event_data[:action])
      when 'push'
        branches = triggers.dig('push', 'branches') || []
        branches.any? { |pattern| File.fnmatch(pattern, event_data[:branch]) }
      when 'issue_comment'
        triggers.dig('issue_comment')&.include?(event_data[:action])
      when 'issue'
        triggers.dig('issue')&.include?(event_data[:action])
      when 'release'
        triggers.dig('release')&.include?(event_data[:action])
      when 'schedule'
        triggers['schedule'].present?
      when 'manual'
        triggers['manual'] != false
      when 'workflow_dispatch'
        triggers['workflow_dispatch'].present?
      else
        false
      end
    end

    def trigger_run!(trigger_type:, trigger_context: {}, triggered_by: nil)
      runs.create!(
        run_number: next_run_number,
        status: 'pending',
        trigger_type: trigger_type,
        trigger_context: trigger_context,
        triggered_by: triggered_by
      )
    end

    def next_run_number
      last_run = runs.order(created_at: :desc).first
      if last_run
        last_number = last_run.run_number.to_s.split('-').last.to_i
        "#{slug}-#{last_number + 1}"
      else
        "#{slug}-1"
      end
    end

    def ordered_steps
      steps.order(position: :asc)
    end

    def feature_enabled?(feature_name)
      features[feature_name.to_s] == true
    end

    def runner_label
      runner_labels&.first || 'ubuntu-latest'
    end

    def generate_workflow_yaml
      CiCd::WorkflowGenerator.new(self).generate
    end

    # ============================================
    # Notification Methods
    # ============================================

    # Get resolved notification recipients
    # Returns array of hashes: [{"type" => "email"|"user_id", "value" => "..."}]
    def resolved_notification_recipients
      return [] if notification_recipients.blank?

      notification_recipients.map do |recipient|
        case recipient["type"]
        when "user_id"
          user = account.users.find_by(id: recipient["value"])
          user ? { "type" => "email", "value" => user.email, "user_id" => user.id } : nil
        when "email"
          { "type" => "email", "value" => recipient["value"] }
        else
          nil
        end
      end.compact
    end

    # Check if notifications are enabled for a specific event
    def notifications_enabled_for?(event)
      notification_settings[event.to_s] != false
    end

    private

    def generate_slug
      return if slug.present?

      base_slug = name.to_s.parameterize
      self.slug = base_slug
      counter = 1

      while account.ci_cd_pipelines.where(slug: slug).where.not(id: id).exists?
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end

    def triggers_format
      return if triggers.blank?

      # All trigger types supported by the webhook normalizer
      valid_trigger_types = %w[pull_request push issue issue_comment release schedule manual workflow_dispatch]
      invalid_keys = triggers.keys - valid_trigger_types

      errors.add(:triggers, "contains invalid trigger types: #{invalid_keys.join(', ')}") if invalid_keys.any?
    end

    def system_pipelines_immutable
      return unless is_system? && (steps_changed? || triggers_changed?)

      errors.add(:base, 'cannot modify system pipeline configuration')
    end
  end
end
