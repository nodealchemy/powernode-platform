# frozen_string_literal: true

module Ai
  class WorkflowTrigger < ApplicationRecord
    self.table_name = "ai_workflow_triggers"

    VALID_EVENT_TYPES = %w[
      user_created user_updated user_deleted
      account_created account_updated account_deleted
      subscription_created subscription_updated subscription_cancelled subscription_renewed
      payment_succeeded payment_failed payment_refunded
      invoice_created invoice_paid invoice_overdue
      workflow_completed workflow_failed
      webhook_received api_call_completed
    ].freeze

    # Associations
    belongs_to :workflow, class_name: "Ai::Workflow", foreign_key: "ai_workflow_id"
    has_many :workflow_runs, class_name: "Ai::WorkflowRun",
             foreign_key: "ai_workflow_trigger_id", dependent: :nullify
    has_many :git_workflow_triggers, foreign_key: "ai_workflow_trigger_id", dependent: :destroy

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :trigger_type, presence: true, inclusion: {
      in: %w[manual webhook schedule event api_call],
      message: "must be a valid trigger type"
    }
    validates :status, presence: true, inclusion: {
      in: %w[active paused disabled error],
      message: "must be a valid trigger status"
    }
    validates :configuration, presence: true
    validate :validate_trigger_configuration
    validate :validate_webhook_configuration, if: :webhook_trigger?
    validate :validate_schedule_configuration, if: :schedule_trigger?
    validate :validate_event_configuration, if: :event_trigger?

    # JSON columns
    attribute :configuration, :json, default: -> { {} }
    attribute :conditions, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :active, -> { where(status: "active", is_active: true) }
    scope :inactive, -> { where.not(status: "active").or(where(is_active: false)) }
    scope :by_type, ->(type) { where(trigger_type: type) }
    scope :manual_triggers, -> { where(trigger_type: "manual") }
    scope :webhook_triggers, -> { where(trigger_type: "webhook") }
    scope :schedule_triggers, -> { where(trigger_type: "schedule") }
    scope :event_triggers, -> { where(trigger_type: "event") }
    scope :api_call_triggers, -> { where(trigger_type: "api_call") }
    scope :due_for_execution, -> {
      where(trigger_type: "schedule", is_active: true, status: "active")
        .where("next_execution_at <= ?", Time.current)
    }

    # Callbacks
    before_validation :set_default_configuration
    before_save :update_next_execution_time, if: -> { schedule_trigger? && schedule_cron.present? && (new_record? || schedule_cron_changed? || status_changed?) }
    after_create :generate_webhook_url_if_needed
    after_update :update_trigger_metadata

    # Type check methods
    def manual_trigger?
      trigger_type == "manual"
    end

    def webhook_trigger?
      trigger_type == "webhook"
    end

    def schedule_trigger?
      trigger_type == "schedule"
    end

    def event_trigger?
      trigger_type == "event"
    end

    def api_call_trigger?
      trigger_type == "api_call"
    end

    # Status check methods
    def active?
      status == "active" && is_active?
    end

    def paused?
      status == "paused"
    end

    def disabled?
      status == "disabled" || !is_active?
    end

    def has_error?
      status == "error"
    end

    def can_trigger?
      active? && workflow.can_execute?
    end

    def trigger_workflow(input_variables = {}, user: nil, context: {})
      raise ArgumentError, "Trigger is not active" unless can_trigger?

      return false unless conditions_met?(input_variables, context)

      begin
        increment!(:trigger_count)
        update_column(:last_triggered_at, Time.current)

        workflow_run = workflow.execute(
          input_variables,
          user: user,
          trigger: self,
          trigger_type: trigger_type
        )

        update!(
          metadata: metadata.merge({
            "last_successful_trigger" => Time.current.iso8601,
            "last_run_id" => workflow_run.run_id
          })
        )

        workflow_run
      rescue StandardError => e
        handle_trigger_error(e)
        raise
      end
    end

    def next_execution_time
      return nil unless schedule_trigger? && schedule_cron.present?

      begin
        cron = Fugit::Cron.new(schedule_cron)
        return nil unless cron

        next_time = cron.next_time(Time.current)
        next_time.respond_to?(:to_t) ? next_time.to_t : next_time
      rescue StandardError => e
        Rails.logger.error "Failed to calculate next execution time for trigger #{id}: #{e.message}"
        nil
      end
    end

    def conditions_met?(input_variables, context = {})
      return true if conditions.blank? || conditions.empty?

      begin
        evaluate_conditions(conditions, input_variables.merge(context))
      rescue StandardError => e
        Rails.logger.error "Failed to evaluate trigger conditions for trigger #{id}: #{e.message}"
        false
      end
    end

    def activate!
      update!(status: "active", is_active: true)
      calculate_next_execution if schedule_trigger?
    end

    def pause!
      update!(status: "paused")
    end

    def disable!
      update!(status: "disabled", is_active: false)
    end

    def reset_error!
      return false unless has_error?

      update!(status: "active", metadata: metadata.except("error_message", "error_timestamp"))
    end

    # Webhook methods
    def webhook_endpoint
      return nil unless webhook_trigger?

      webhook_url
    end

    def verify_webhook_signature(payload, signature)
      # No secret configured means accept all
      return true if webhook_secret.blank?
      return false if signature.blank?

      expected_signature = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, payload.to_s)
      ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature)
    end

    # Event methods
    def event_types
      return [] unless event_trigger?

      configuration["event_types"] || []
    end

    def matches_event?(event_type)
      return false unless active? && event_trigger?

      event_types.include?(event_type)
    end

    # Schedule methods
    def due_for_execution?
      return false unless schedule_trigger? && active?
      return false if next_execution_at.blank?

      next_execution_at <= Time.current
    end

    # Summary methods
    def execution_summary
      recent_runs = workflow_runs.where("created_at >= ?", 24.hours.ago)
      successful_runs = recent_runs.where(status: "completed")

      {
        total_triggers: trigger_count,
        recent_triggers: recent_runs.count,
        success_rate: recent_runs.count.positive? ? (successful_runs.count.to_f / recent_runs.count * 100).round(1) : 0.0,
        average_execution_time: calculate_average_execution_time(recent_runs),
        last_triggered: last_triggered_at,
        next_execution: next_execution_at,
        status: status
      }
    end

    private

    def set_default_configuration
      return if configuration.present?

      self.configuration = case trigger_type
      when "manual"
        { "require_confirmation" => false }
      when "webhook"
        { "method" => "POST", "content_type" => "application/json", "payload_mapping" => {} }
      when "schedule"
        { "timezone" => "UTC", "max_executions" => nil, "skip_if_running" => true }
      when "event"
        { "event_types" => [], "debounce_seconds" => 0 }
      when "api_call"
        { "require_authentication" => true, "rate_limit" => 100 }
      else
        {}
      end
    end

    def update_next_execution_time
      return unless schedule_trigger? && active?
      calculate_next_execution
    end

    def calculate_next_execution
      next_time = next_execution_time
      return unless next_time

      if persisted?
        update_column(:next_execution_at, next_time)
      else
        self.next_execution_at = next_time
      end
    end

    def generate_webhook_url_if_needed
      return unless webhook_trigger? && webhook_url.blank?

      generated_url = generate_webhook_url
      update_column(:webhook_url, generated_url) if generated_url
    end

    def generate_webhook_url
      webhook_token = SecureRandom.urlsafe_base64(32)
      base_url = Rails.application.routes.url_helpers.root_url(host: ENV["APP_DOMAIN"] || "localhost:3000")
      "#{base_url}api/v1/ai/workflows/#{workflow.id}/triggers/#{id}/webhook/#{webhook_token}"
    end

    def update_trigger_metadata
      return unless saved_changes.any?

      self.metadata = metadata.merge({
        "last_modified_at" => Time.current.iso8601,
        "version" => (metadata["version"] || 0) + 1
      })
    end

    def validate_trigger_configuration
      return unless configuration.present?

      case trigger_type
      when "schedule"
        errors.add(:schedule_cron, "must be present for schedule triggers") if schedule_cron.blank?
      when "webhook"
        errors.add(:configuration, "must specify method for webhook triggers") if configuration["method"].blank?
      when "event"
        if configuration["event_types"].blank? || !configuration["event_types"].is_a?(Array)
          errors.add(:configuration, "must specify event_types array for event triggers")
        end
      end
    end

    def validate_webhook_configuration
      return unless webhook_trigger?

      if configuration["method"].present?
        valid_methods = %w[GET POST PUT PATCH DELETE]
        unless valid_methods.include?(configuration["method"].upcase)
          errors.add(:configuration, "method must be a valid HTTP method")
        end
      end
    end

    def validate_schedule_configuration
      return unless schedule_trigger?

      if schedule_cron.present?
        begin
          cron = Fugit::Cron.new(schedule_cron)
          errors.add(:schedule_cron, "is not a valid cron expression") if cron.nil?
        rescue StandardError
          errors.add(:schedule_cron, "is not a valid cron expression")
        end
      end
    end

    def validate_event_configuration
      return unless event_trigger?
      return unless configuration["event_types"].is_a?(Array)

      invalid_types = configuration["event_types"] - VALID_EVENT_TYPES
      if invalid_types.any?
        errors.add(:configuration, "contains invalid event types: #{invalid_types.join(', ')}")
      end
    end

    def evaluate_conditions(conditions_hash, variables)
      return true if conditions_hash.blank?

      if conditions_hash["rules"].present?
        rules = conditions_hash["rules"]
        logic = conditions_hash["logic"] || "AND"
        results = rules.map { |rule| evaluate_single_condition(rule, variables) }

        case logic.upcase
        when "AND"
          results.all?
        when "OR"
          results.any?
        else
          false
        end
      else
        true
      end
    end

    def evaluate_single_condition(rule, variables)
      variable_path = rule["variable"]
      operator = rule["operator"]
      expected_value = rule["value"]
      actual_value = get_nested_value(variables, variable_path)

      case operator
      when "=="
        actual_value == expected_value
      when "!="
        actual_value != expected_value
      when ">"
        actual_value.to_f > expected_value.to_f
      when ">="
        actual_value.to_f >= expected_value.to_f
      when "<"
        actual_value.to_f < expected_value.to_f
      when "<="
        actual_value.to_f <= expected_value.to_f
      when "contains"
        actual_value.to_s.include?(expected_value.to_s)
      when "exists"
        !actual_value.nil?
      when "not_exists"
        actual_value.nil?
      else
        false
      end
    end

    def get_nested_value(hash, path)
      return nil unless hash.is_a?(Hash)

      keys = path.split(".")
      current_value = hash

      keys.each do |key|
        case current_value
        when Hash
          current_value = current_value[key] || current_value[key.to_sym]
        else
          return nil
        end
      end

      current_value
    end

    def handle_trigger_error(error)
      Rails.logger.error "Trigger #{id} failed: #{error.message}"

      update!(
        status: "error",
        metadata: metadata.merge({
          "error_message" => error.message,
          "error_timestamp" => Time.current.iso8601,
          "error_count" => (metadata["error_count"] || 0) + 1
        })
      )
    end

    def calculate_average_execution_time(runs)
      completed_runs = runs.where.not(completed_at: nil).where.not(started_at: nil)
      return 0.0 if completed_runs.count.zero?

      total_time = completed_runs.sum { |run| (run.completed_at - run.started_at).to_f }
      (total_time / completed_runs.count).round(2)
    end
  end
end
