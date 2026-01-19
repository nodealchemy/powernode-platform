# frozen_string_literal: true

module Marketplace
  class EndpointCall < ApplicationRecord
    # Associations
    belongs_to :endpoint, class_name: "Marketplace::Endpoint", foreign_key: "app_endpoint_id"
    belongs_to :account, optional: true

    # Validations
    validates :status_code, presence: true,
              numericality: { greater_than_or_equal_to: 100, less_than_or_equal_to: 599 }
    validates :response_time_ms, presence: true,
              numericality: { greater_than_or_equal_to: 0 }

    # Scopes
    scope :successful, -> { where(status_code: 200..299) }
    scope :client_errors, -> { where(status_code: 400..499) }
    scope :server_errors, -> { where(status_code: 500..599) }
    scope :with_errors, -> { where.not(error_message: [nil, ""]) }
    scope :recent, -> { order(called_at: :desc) }
    scope :last_24h, -> { where("called_at > ?", 24.hours.ago) }
    scope :last_7d, -> { where("called_at > ?", 7.days.ago) }
    scope :last_30d, -> { where("called_at > ?", 30.days.ago) }

    # Callbacks
    before_save :set_called_at, if: -> { called_at.blank? }

    # Instance methods
    def successful?
      (200..299).include?(status_code)
    end

    def client_error?
      (400..499).include?(status_code)
    end

    def server_error?
      (500..599).include?(status_code)
    end

    def has_error?
      error_message.present?
    end

    def response_time_seconds
      response_time_ms / 1000.0
    end

    def request_size_kb
      return 0 unless request_size_bytes
      (request_size_bytes / 1024.0).round(2)
    end

    def response_size_kb
      return 0 unless response_size_bytes
      (response_size_bytes / 1024.0).round(2)
    end

    def status_category
      case status_code
      when 200..299 then "success"
      when 300..399 then "redirect"
      when 400..499 then "client_error"
      when 500..599 then "server_error"
      else "unknown"
      end
    end

    def app
      endpoint.app
    end

    # Alias for backward compatibility
    def app_endpoint
      endpoint
    end

    # Class methods
    def self.grouped_by_status
      group(:status_code).count
    end

    def self.grouped_by_hour(hours = 24)
      where("called_at > ?", hours.hours.ago)
        .group_by_hour(:called_at, last: hours)
        .count
    end

    def self.average_response_time
      average(:response_time_ms)&.to_f&.round(2) || 0
    end

    def self.success_rate
      total = count
      return 0 if total.zero?

      successful_count = successful.count
      ((successful_count.to_f / total) * 100).round(2)
    end

    private

    def set_called_at
      self.called_at = Time.current
    end
  end
end

# Backward compatibility alias
AppEndpointCall = Marketplace::EndpointCall unless defined?(AppEndpointCall)
