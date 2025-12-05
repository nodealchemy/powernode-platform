# frozen_string_literal: true

# CircuitBreakerEvent tracks individual events for circuit breaker monitoring
class CircuitBreakerEvent < ApplicationRecord
  # ==========================================
  # Associations
  # ==========================================
  belongs_to :circuit_breaker

  # ==========================================
  # Validations
  # ==========================================
  validates :event_type, presence: true, inclusion: {
    in: %w[success failure timeout state_change],
    message: 'must be a valid event type'
  }

  # ==========================================
  # Scopes
  # ==========================================
  scope :successes, -> { where(event_type: 'success') }
  scope :failures, -> { where(event_type: 'failure') }
  scope :timeouts, -> { where(event_type: 'timeout') }
  scope :state_changes, -> { where(event_type: 'state_change') }
  scope :recent, ->(duration = 1.hour) { where('created_at > ?', duration.ago) }
  scope :for_circuit_breaker, ->(breaker_id) { where(circuit_breaker_id: breaker_id) }
  scope :by_date, ->(date) { where('DATE(created_at) = ?', date) }

  # ==========================================
  # Public Methods
  # ==========================================

  def success?
    event_type == 'success'
  end

  def failure?
    event_type == 'failure'
  end

  def timeout?
    event_type == 'timeout'
  end

  def state_change?
    event_type == 'state_change'
  end
end
