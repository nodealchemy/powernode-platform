# frozen_string_literal: true

module Monitoring
  # CircuitBreaker monitors service health and implements circuit breaker pattern
  # States: closed (normal) → open (failing) → half_open (testing) → closed
  class CircuitBreaker < ApplicationRecord
    self.table_name = "circuit_breakers"

    # ==========================================
    # Concerns
    # ==========================================
    include Auditable

    # ==========================================
    # Associations
    # ==========================================
    has_many :circuit_breaker_events, class_name: "Monitoring::CircuitBreakerEvent", foreign_key: "circuit_breaker_id", dependent: :destroy

    # ==========================================
    # Validations
    # ==========================================
    validates :name, presence: true
    validates :service, presence: true
    validates :state, presence: true, inclusion: {
      in: %w[closed open half_open],
      message: "must be closed, open, or half_open"
    }
    validates :failure_threshold, numericality: { greater_than: 0 }
    validates :success_threshold, numericality: { greater_than: 0 }
    validates :timeout_seconds, numericality: { greater_than: 0 }
    validates :reset_timeout_seconds, numericality: { greater_than: 0 }

    validate :validate_configuration_format

    # Ensure unique name per service
    validates :name, uniqueness: { scope: :service }

    # ==========================================
    # Scopes
    # ==========================================
    scope :closed, -> { where(state: "closed") }
    scope :open, -> { where(state: "open") }
    scope :half_open, -> { where(state: "half_open") }
    scope :for_service, ->(service_name) { where(service: service_name) }
    scope :for_provider, ->(provider_name) { where(provider: provider_name) }
    scope :recently_failed, -> { where("last_failure_at > ?", 1.hour.ago) }
    scope :healthy, -> { where(state: "closed") }
    scope :unhealthy, -> { where(state: %w[open half_open]) }

    # ==========================================
    # Callbacks
    # ==========================================
    before_validation :set_default_values, on: :create
    after_update :log_state_change, if: :saved_change_to_state?
    after_update :check_auto_reset, if: -> { open? && should_attempt_reset? }

    # ==========================================
    # Public Methods
    # ==========================================

    # State check methods
    def closed?
      state == "closed"
    end

    def open?
      state == "open"
    end

    def half_open?
      state == "half_open"
    end

    # Check if circuit breaker allows execution
    def allow_request?
      case state
      when "closed"
        true
      when "half_open"
        true # Allow limited requests to test recovery
      when "open"
        false
      else
        false
      end
    end

    # Record successful execution
    def record_success(duration_ms: nil)
      transaction do
        reload(lock: true)

        case state
        when "closed"
          # Reset failure count on success
          update!(
            failure_count: 0,
            success_count: success_count + 1,
            last_success_at: Time.current
          )
        when "half_open"
          # Increment success count in half-open state
          new_success_count = success_count + 1

          if new_success_count >= success_threshold
            # Recovered - transition to closed
            transition_to_closed!
          else
            # Still testing - increment success count
            update!(
              success_count: new_success_count,
              last_success_at: Time.current
            )
          end
        end

        # Record event
        record_event("success", nil, duration_ms)

        # Update metrics
        update_metrics("successes", duration_ms)
      end
    end

    # Record failed execution
    def record_failure(error_message: nil, duration_ms: nil)
      transaction do
        reload(lock: true)

        case state
        when "closed"
          # Increment failure count
          new_failure_count = failure_count + 1

          if new_failure_count >= failure_threshold
            # Too many failures - open circuit
            transition_to_open!(error_message)
          else
            # Still within threshold
            update!(
              failure_count: new_failure_count,
              last_failure_at: Time.current
            )
          end
        when "half_open"
          # Failed during testing - reopen circuit
          transition_to_open!(error_message)
        end

        # Record event
        record_event("failure", error_message, duration_ms)

        # Update metrics
        update_metrics("failures", duration_ms)
      end
    end

    # Record timeout
    def record_timeout
      record_failure(error_message: "Request timeout exceeded", duration_ms: timeout_seconds * 1000)
    end

    # Manual reset to closed state
    def reset!
      transition_to_closed!
    end

    # Get recent events
    def recent_events(limit = 10)
      circuit_breaker_events.order(created_at: :desc).limit(limit)
    end

    # Calculate health metrics
    def health_metrics
      recent_events = circuit_breaker_events.where("created_at > ?", 1.hour.ago)
      total_events = recent_events.count

      return default_health_metrics if total_events.zero?

      {
        state: state,
        failure_count: failure_count,
        success_count: success_count,
        total_requests: total_events,
        success_rate: calculate_success_rate(recent_events),
        failure_rate: calculate_failure_rate(recent_events),
        avg_duration_ms: calculate_avg_duration(recent_events),
        last_failure: last_failure_at,
        last_success: last_success_at,
        metrics: metrics
      }
    end

    # ==========================================
    # Private Methods
    # ==========================================
    private

    def set_default_values
      self.state ||= "closed"
      self.failure_count ||= 0
      self.success_count ||= 0
      self.failure_threshold ||= 5
      self.success_threshold ||= 2
      self.timeout_seconds ||= 30
      self.reset_timeout_seconds ||= 60
      self.configuration ||= {}
      self.metrics ||= {}
    end

    def validate_configuration_format
      return if configuration.blank?

      unless configuration.is_a?(Hash)
        errors.add(:configuration, "must be a hash")
      end
    end

    def transition_to_open!(error_message = nil)
      update!(
        state: "open",
        opened_at: Time.current,
        failure_count: failure_count + 1,
        success_count: 0,
        last_failure_at: Time.current
      )

      record_state_change("open", error_message)
    end

    def transition_to_half_open!
      update!(
        state: "half_open",
        half_opened_at: Time.current,
        success_count: 0
      )

      record_state_change("half_open")
    end

    def transition_to_closed!
      update!(
        state: "closed",
        failure_count: 0,
        success_count: 0,
        opened_at: nil,
        half_opened_at: nil,
        last_success_at: Time.current
      )

      record_state_change("closed")
    end

    def should_attempt_reset?
      return false unless opened_at.present?
      Time.current >= (opened_at + reset_timeout_seconds.seconds)
    end

    def check_auto_reset
      transition_to_half_open! if should_attempt_reset?
    end

    def record_event(event_type, error_message = nil, duration_ms = nil)
      circuit_breaker_events.create!(
        event_type: event_type,
        error_message: error_message,
        duration_ms: duration_ms,
        failure_count: failure_count
      )
    end

    def record_state_change(new_state, error_message = nil)
      circuit_breaker_events.create!(
        event_type: "state_change",
        old_state: state_was,
        new_state: new_state,
        error_message: error_message,
        failure_count: failure_count
      )
    end

    def log_state_change
      Rails.logger.info "CircuitBreaker [#{name}:#{service}] state changed: #{state_was} → #{state}"
    end

    def update_metrics(metric_type, duration_ms)
      self.metrics ||= {}
      self.metrics[metric_type] ||= 0
      self.metrics[metric_type] += 1
      self.metrics["last_duration_ms"] = duration_ms if duration_ms
      save!
    end

    def calculate_success_rate(events)
      successes = events.where(event_type: "success").count
      total = events.count
      return 0.0 if total.zero?
      (successes.to_f / total * 100).round(2)
    end

    def calculate_failure_rate(events)
      failures = events.where(event_type: "failure").count
      total = events.count
      return 0.0 if total.zero?
      (failures.to_f / total * 100).round(2)
    end

    def calculate_avg_duration(events)
      durations = events.where.not(duration_ms: nil).pluck(:duration_ms)
      return 0 if durations.empty?
      (durations.sum / durations.size.to_f).round(2)
    end

    def default_health_metrics
      {
        state: state,
        failure_count: failure_count,
        success_count: success_count,
        total_requests: 0,
        success_rate: 0.0,
        failure_rate: 0.0,
        avg_duration_ms: 0,
        last_failure: last_failure_at,
        last_success: last_success_at,
        metrics: metrics
      }
    end
  end
end

# Backwards compatibility alias
