# frozen_string_literal: true

class AiWorkflowTrigger < ApplicationRecord
  # Authentication & Authorization
  belongs_to :ai_workflow

  # Associations
  has_many :ai_workflow_runs, dependent: :nullify
  has_many :git_workflow_triggers, dependent: :destroy

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

  # Trigger execution methods
  def can_trigger?
    active? && ai_workflow.can_execute?
  end

  def trigger_workflow(input_variables = {}, user: nil, context: {})
    raise ArgumentError, "Trigger is not active" unless can_trigger?

    # Validate input against conditions
    return false unless conditions_met?(input_variables, context)

    begin
      # Record trigger event
      increment!(:trigger_count)
      update_column(:last_triggered_at, Time.current)

      # Execute workflow
      workflow_run = ai_workflow.execute(
        input_variables,
        user: user,
        trigger: self,
        trigger_type: trigger_type
      )

      # Update trigger metadata
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

  # Schedule-specific methods
  def next_execution_time
    return nil unless schedule_trigger? && schedule_cron.present?

    begin
      cron = Fugit::Cron.new(schedule_cron)
      return nil unless cron

      next_time = cron.next_time(Time.current)
      # Convert EtOrbi::EoTime to Time using to_t method
      next_time.respond_to?(:to_t) ? next_time.to_t : next_time
    rescue StandardError => e
      Rails.logger.error "Failed to calculate next execution time for trigger #{id}: #{e.message}"
      nil
    end
  end

  def calculate_next_execution
    return unless schedule_trigger?

    next_time = next_execution_time
    return unless next_time

    if persisted?
      update_column(:next_execution_at, next_time)
    else
      self.next_execution_at = next_time
    end
  end

  def due_for_execution?
    schedule_trigger? && active? && next_execution_at.present? && next_execution_at <= Time.current
  end

  # Webhook-specific methods
  def webhook_endpoint
    return nil unless webhook_trigger?

    webhook_url || generate_webhook_url
  end

  def verify_webhook_signature(payload, signature)
    return true unless webhook_secret.present?

    expected_signature = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, payload)
    ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
  end

  def process_webhook_payload(payload, headers = {})
    return false unless webhook_trigger? && can_trigger?

    begin
      # Parse webhook payload
      input_variables = parse_webhook_payload(payload, headers)

      # Add webhook metadata
      context = {
        "webhook" => {
          "headers" => headers,
          "timestamp" => Time.current.iso8601,
          "source_ip" => headers["X-Forwarded-For"] || headers["Remote-Addr"]
        }
      }

      # Trigger workflow
      trigger_workflow(input_variables, context: context)
    rescue StandardError => e
      handle_trigger_error(e)
      false
    end
  end

  # Event-specific methods
  def event_types
    return [] unless event_trigger?

    configuration["event_types"] || []
  end

  def matches_event?(event_type, event_data = {})
    return false unless event_trigger? && active?
    return false unless event_types.include?(event_type)

    # Check event conditions
    conditions_met?({}, { "event" => { "type" => event_type, "data" => event_data } })
  end

  def process_event(event_type, event_data = {}, user: nil)
    return false unless matches_event?(event_type, event_data)

    begin
      input_variables = extract_variables_from_event(event_data)
      context = {
        "event" => {
          "type" => event_type,
          "data" => event_data,
          "timestamp" => Time.current.iso8601
        }
      }

      trigger_workflow(input_variables, user: user, context: context)
    rescue StandardError => e
      handle_trigger_error(e)
      false
    end
  end

  # Condition evaluation
  def conditions_met?(input_variables, context = {})
    return true if conditions.blank? || conditions.empty?

    begin
      evaluate_conditions(conditions, input_variables.merge(context))
    rescue StandardError => e
      Rails.logger.error "Failed to evaluate trigger conditions for trigger #{id}: #{e.message}"
      false
    end
  end

  # Trigger management
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
    return unless has_error?

    update!(
      status: "active",
      metadata: metadata.except("error_message", "error_timestamp")
    )
  end

  # Trigger statistics
  def execution_summary(days = 30)
    runs = ai_workflow_runs.where("created_at >= ?", days.days.ago)

    {
      total_triggers: trigger_count,
      recent_triggers: runs.count,
      success_rate: calculate_success_rate(runs),
      average_execution_time: runs.where(status: "completed").average(:duration_ms)&.to_i || 0,
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
                          {
                            "method" => "POST",
                            "content_type" => "application/json",
                            "payload_mapping" => {}
                          }
    when "schedule"
                          {
                            "timezone" => "UTC",
                            "max_executions" => nil,
                            "skip_if_running" => true
                          }
    when "event"
                          {
                            "event_types" => [],
                            "debounce_seconds" => 0
                          }
    when "api_call"
                          {
                            "require_authentication" => true,
                            "rate_limit" => 100
                          }
    else
                          {}
    end
  end

  def update_next_execution_time
    return unless schedule_trigger? && active?

    calculate_next_execution
  end

  def generate_webhook_url_if_needed
    return unless webhook_trigger? && webhook_url.blank?

    generated_url = generate_webhook_url
    update_column(:webhook_url, generated_url) if generated_url
  end

  def generate_webhook_url
    # Generate a unique webhook URL for this trigger
    webhook_token = SecureRandom.urlsafe_base64(32)
    base_url = Rails.application.routes.url_helpers.root_url(host: ENV["APP_DOMAIN"] || "localhost:3000")

    "#{base_url}api/v1/ai/workflows/#{ai_workflow.id}/triggers/#{id}/webhook/#{webhook_token}"
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

    event_types = configuration["event_types"]
    if event_types.present? && event_types.is_a?(Array)
      valid_event_types = %w[
        user_created user_updated user_deleted
        subscription_created subscription_updated subscription_cancelled
        payment_succeeded payment_failed
        invoice_created invoice_paid
        ai_agent_completed ai_agent_failed
        workflow_completed workflow_failed
        custom_event
        git_push git_pull_request git_pull_request_review
        git_workflow_run git_check_run git_deployment
        git_release git_tag git_issue git_issue_comment
        pipeline_completed pipeline_failed pipeline_cancelled
      ]

      invalid_types = event_types - valid_event_types
      if invalid_types.any?
        errors.add(:configuration, "contains invalid event types: #{invalid_types.join(', ')}")
      end
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
    when "starts_with"
      actual_value.to_s.start_with?(expected_value.to_s)
    when "ends_with"
      actual_value.to_s.end_with?(expected_value.to_s)
    when "in"
      Array(expected_value).include?(actual_value)
    when "not_in"
      !Array(expected_value).include?(actual_value)
    when "exists"
      !actual_value.nil?
    when "not_exists"
      actual_value.nil?
    when "regex_match"
      actual_value.to_s.match?(Regexp.new(expected_value.to_s))
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

  def parse_webhook_payload(payload, headers)
    content_type = headers["Content-Type"] || "application/json"

    case content_type.downcase
    when /application\/json/
      JSON.parse(payload)
    when /application\/x-www-form-urlencoded/
      Rack::Utils.parse_query(payload)
    else
      { "raw_payload" => payload }
    end
  rescue JSON::ParserError
    { "raw_payload" => payload }
  end

  def extract_variables_from_event(event_data)
    mapping = configuration["variable_mapping"] || {}

    if mapping.any?
      result = {}
      mapping.each do |variable_name, path|
        result[variable_name] = get_nested_value(event_data, path)
      end
      result
    else
      event_data
    end
  end

  def calculate_success_rate(runs)
    return 0.0 if runs.empty?

    successful = runs.where(status: "completed").count
    (successful.to_f / runs.count * 100).round(2)
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
end
