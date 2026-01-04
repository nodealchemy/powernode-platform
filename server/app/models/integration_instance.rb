# frozen_string_literal: true

class IntegrationInstance < ApplicationRecord
  # ==================== Concerns ====================
  include Auditable

  # ==================== Constants ====================
  STATUSES = %w[pending active paused error disabled].freeze
  HEALTH_STATUSES = %w[healthy degraded unhealthy unknown].freeze

  # ==================== Associations ====================
  belongs_to :account
  belongs_to :integration_template
  belongs_to :integration_credential, optional: true
  belongs_to :created_by_user, class_name: "User", optional: true

  has_many :integration_executions, dependent: :destroy

  # ==================== Validations ====================
  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, format: { with: /\A[a-z0-9_-]+\z/ }
  validates :slug, uniqueness: { scope: :account_id }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :health_status, inclusion: { in: HEALTH_STATUSES }, allow_nil: true
  validate :credential_matches_template_requirements

  # ==================== Scopes ====================
  scope :active, -> { where(status: "active") }
  scope :pending, -> { where(status: "pending") }
  scope :paused, -> { where(status: "paused") }
  scope :errored, -> { where(status: "error") }
  scope :disabled, -> { where(status: "disabled") }
  scope :healthy, -> { where(health_status: "healthy") }
  scope :unhealthy, -> { where(health_status: %w[degraded unhealthy]) }
  scope :by_template, ->(template_id) { where(integration_template_id: template_id) }
  scope :by_type, ->(type) { joins(:integration_template).where(integration_templates: { integration_type: type }) }
  scope :recent, -> { order(created_at: :desc) }

  # ==================== Callbacks ====================
  before_validation :generate_slug, on: :create
  before_save :sanitize_jsonb_fields
  after_create :increment_template_install_count

  # ==================== Instance Methods ====================

  def instance_summary
    {
      id: id,
      name: name,
      slug: slug,
      status: status,
      health_status: health_status,
      template: integration_template.template_summary,
      execution_count: execution_count,
      success_rate: success_rate,
      last_executed_at: last_executed_at
    }
  end

  def instance_details
    instance_summary.merge(
      description: description,
      configuration: configuration,
      runtime_state: runtime_state,
      health_metrics: health_metrics,
      success_count: success_count,
      failure_count: failure_count,
      average_duration_ms: average_duration_ms,
      last_success_at: last_success_at,
      last_failure_at: last_failure_at,
      last_error: last_error,
      last_health_check_at: last_health_check_at,
      consecutive_failures: consecutive_failures,
      credential_id: integration_credential_id,
      created_at: created_at,
      updated_at: updated_at
    )
  end

  def success_rate
    return 0 if execution_count.zero?
    ((success_count.to_f / execution_count) * 100).round(2)
  end

  def merged_configuration
    integration_template.default_configuration.deep_merge(configuration)
  end

  def activate!
    update!(status: "active")
  end

  def pause!
    update!(status: "paused")
  end

  def disable!
    update!(status: "disabled")
  end

  def mark_error!(error_message = nil)
    update!(
      status: "error",
      last_error: error_message,
      consecutive_failures: consecutive_failures + 1
    )
  end

  def record_execution!(success:, duration_ms: nil, error: nil)
    updates = {
      execution_count: execution_count + 1,
      last_executed_at: Time.current
    }

    if success
      updates[:success_count] = success_count + 1
      updates[:last_success_at] = Time.current
      updates[:consecutive_failures] = 0
      updates[:last_error] = nil
    else
      updates[:failure_count] = failure_count + 1
      updates[:last_failure_at] = Time.current
      updates[:consecutive_failures] = consecutive_failures + 1
      updates[:last_error] = error&.truncate(1000)
    end

    if duration_ms
      # Calculate running average
      total_duration = (average_duration_ms || 0) * (execution_count - 1) + duration_ms
      updates[:average_duration_ms] = total_duration / execution_count
    end

    update!(updates)

    # Auto-mark as error if too many consecutive failures
    mark_error!(error) if consecutive_failures >= 5 && status == "active"
  end

  def update_health!(status, metrics = {})
    update!(
      health_status: status,
      health_metrics: health_metrics.merge(metrics),
      last_health_check_at: Time.current
    )
  end

  def can_execute?
    status == "active" && health_status != "unhealthy"
  end

  def template_type
    integration_template.integration_type
  end

  private

  def generate_slug
    return if slug.present?

    base_slug = name.to_s.parameterize
    self.slug = base_slug

    counter = 1
    while IntegrationInstance.where(account_id: account_id, slug: slug).exists?
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def sanitize_jsonb_fields
    self.configuration = {} if configuration.blank?
    self.runtime_state = {} if runtime_state.blank?
    self.health_metrics = {} if health_metrics.blank?
  end

  def credential_matches_template_requirements
    return unless integration_template&.requires_credentials?

    if integration_credential.blank?
      errors.add(:integration_credential, "is required for this integration type")
      return
    end

    required_type = integration_template.required_credential_type
    return unless required_type.present?

    unless integration_credential.credential_type == required_type
      errors.add(:integration_credential, "must be of type #{required_type}")
    end
  end

  def increment_template_install_count
    integration_template.increment_install!
  end
end
