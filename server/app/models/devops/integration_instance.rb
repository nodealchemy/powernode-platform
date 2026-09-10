# frozen_string_literal: true

module Devops
  class IntegrationInstance < ApplicationRecord
    # ==================== Concerns ====================
    include Auditable

    # ==================== Table Name ====================
    self.table_name = "devops_integration_instances"

    # ==================== Constants ====================
    STATUSES = %w[pending active paused error disabled].freeze
    HEALTH_STATUSES = %w[healthy degraded unhealthy unknown].freeze

    # Consecutive FAILED health probes after which an active integration is
    # auto-paused. DB-driven per the no-hardcoded-thresholds convention; the
    # literal is the fallback because seeds never re-run on a deployment that
    # already booted, so an existing install has no row and must still pause.
    # The value used to be a literal `3` in the worker job, where the server
    # could neither read it nor enforce it.
    HEALTH_FAILURE_THRESHOLD_SETTING = "devops_integration_health_failure_threshold"
    DEFAULT_HEALTH_FAILURE_THRESHOLD = 3

    # ==================== Associations ====================
    belongs_to :account
    belongs_to :template, class_name: "Devops::IntegrationTemplate", foreign_key: "integration_template_id"
    belongs_to :credential, class_name: "Devops::IntegrationCredential", foreign_key: "integration_credential_id", optional: true
    belongs_to :created_by_user, class_name: "User", optional: true

    has_many :executions, class_name: "Devops::IntegrationExecution", foreign_key: "integration_instance_id", dependent: :destroy

    # Backward compatibility aliases
    def integration_template
      template
    end

    def integration_credential
      credential
    end

    def integration_executions
      executions
    end

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
    scope :by_type, ->(type) { joins(:template).where(devops_integration_templates: { integration_type: type }) }
    scope :recent, -> { order(created_at: :desc) }

    # ==================== Callbacks ====================
    before_validation :generate_slug, on: :create
    before_save :sanitize_jsonb_fields
    after_create :increment_template_install_count

    # ==================== Class Methods ====================

    # A non-positive or absent setting means "unconfigured", not "pause on the
    # first failure" — a 0 threshold would auto-pause every integration on its
    # first failed probe, so it falls back rather than being honoured.
    def self.health_failure_threshold
      configured = SiteSetting.get(HEALTH_FAILURE_THRESHOLD_SETTING).to_i
      configured.positive? ? configured : DEFAULT_HEALTH_FAILURE_THRESHOLD
    end

    # ==================== Instance Methods ====================

    def instance_summary
      {
        id: id,
        name: name,
        slug: slug,
        status: status,
        health_status: health_status,
        template: template.template_summary,
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
      template.default_configuration.deep_merge(configuration)
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
        # Running average INCLUDING this execution. `execution_count` here is still
        # the pre-increment value (the +1 lives in `updates` and is not yet
        # persisted), so the prior sample count IS execution_count and the new
        # count is execution_count + 1 — never zero. The previous code divided by
        # `execution_count` (0 on the first execution), producing an infinite value
        # that overflowed the decimal(10,2) column (PG::NumericValueOutOfRange).
        prior_count = execution_count
        total_duration = (average_duration_ms || 0) * prior_count + duration_ms
        updates[:average_duration_ms] = (total_duration.to_f / (prior_count + 1)).round(2)
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

    # Record the outcome of a health PROBE (a connection test), deriving the
    # health verdict from the outcome plus the consecutive-failure streak and
    # persisting it through `#update_health!` — which stays the single writer of
    # `health_status` / `health_metrics` / `last_health_check_at`.
    #
    # Until A8 this method did not exist, `#update_health!` had zero call sites,
    # and the worker sweep instead PATCHed a `health_metrics` jsonb blob whose
    # nested keys nothing reads. The `integration_health` verb buckets the
    # COLUMN, so it could only ever answer `unknown`.
    #
    # Returns true when this probe auto-paused the integration.
    def record_health_probe!(success:, error: nil, metrics: {})
      threshold = self.class.health_failure_threshold
      failures = success ? 0 : consecutive_failures.to_i + 1

      # `unhealthy`, not `degraded`, at the threshold: `#can_execute?` returns
      # false on unhealthy, which is the truth once the connection test has
      # failed enough times to pause the integration.
      derived = if success
        "healthy"
      elsif failures >= threshold
        "unhealthy"
      else
        "degraded"
      end

      self.consecutive_failures = failures
      self.last_error = success ? nil : error&.to_s&.truncate(1000)
      update_health!(derived, metrics)

      auto_pause_for_health!(failures: failures, threshold: threshold)
    end

    # The auto-pause DECISION, guarded here rather than at the mechanism:
    # `#pause!` is a bare `update!` that would happily drag a `disabled`
    # integration back to `paused`, undoing an operator's retirement, or
    # re-pause one already paused. Only an ACTIVE integration whose failure
    # streak has reached the threshold is paused.
    def auto_pause_for_health!(failures: consecutive_failures.to_i, threshold: self.class.health_failure_threshold)
      return false unless status == "active"
      return false if failures < threshold

      pause!
      true
    end

    def can_execute?
      status == "active" && health_status != "unhealthy"
    end

    def template_type
      template.integration_type
    end

    private

    def generate_slug
      return if slug.present?

      base_slug = name.to_s.parameterize
      self.slug = base_slug

      counter = 1
      while Devops::IntegrationInstance.where(account_id: account_id, slug: slug).exists?
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
      return unless template&.requires_credentials?

      if credential.blank?
        errors.add(:credential, "is required for this integration type")
        return
      end

      required_type = template.required_credential_type
      return unless required_type.present?

      unless credential.credential_type == required_type
        errors.add(:credential, "must be of type #{required_type}")
      end
    end

    def increment_template_install_count
      template.increment_install!
    end
  end
end
