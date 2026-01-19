# frozen_string_literal: true

module Marketplace
  class Webhook < ApplicationRecord
    # Associations
    belongs_to :app, class_name: "Marketplace::Definition", foreign_key: "app_id"
    has_many :webhook_deliveries, class_name: "Marketplace::WebhookDelivery", foreign_key: "app_webhook_id", dependent: :destroy

    # Validations
    validates :name, presence: true, length: { minimum: 1, maximum: 255 }
    validates :slug, presence: true, length: { minimum: 1, maximum: 255 }
    validates :event_type, presence: true, length: { minimum: 1, maximum: 100 }
    validates :url, presence: true, length: { minimum: 1, maximum: 1000 }
    validates :http_method, presence: true, inclusion: {
      in: %w[POST PUT PATCH],
      message: "must be POST, PUT, or PATCH"
    }
    validates :timeout_seconds, presence: true,
              numericality: { greater_than: 0, less_than_or_equal_to: 300 }
    validates :max_retries, presence: true,
              numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }
    validates :slug, uniqueness: { scope: :app_id, message: "must be unique per app" }
    validates :content_type, presence: true

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :by_event, ->(event_type) { where(event_type: event_type) }
    scope :by_app, ->(app) { where(app: app) }

    # Callbacks
    before_validation :normalize_fields
    before_validation :generate_slug, if: -> { slug.blank? }
    before_validation :generate_secret_token, if: -> { secret_token.blank? }
    after_create :log_webhook_creation
    after_update :log_webhook_updates

    # Instance methods
    def active?
      is_active
    end

    def payload_template_json
      return {} if payload_template.blank?
      payload_template.is_a?(Hash) ? payload_template : {}
    end

    def retry_config_json
      default_config = {
        "backoff_type" => "exponential",
        "initial_delay" => 1,
        "max_delay" => 300
      }

      return default_config if retry_config.blank?
      retry_config.is_a?(Hash) ? retry_config.merge(default_config) : default_config
    end

    def authentication_json
      return {} if authentication.blank?
      authentication.is_a?(Hash) ? authentication : {}
    end

    def headers_json
      default_headers = {
        "Content-Type" => content_type,
        "User-Agent" => "Powernode-Webhook/1.0"
      }

      return default_headers if headers.blank?
      custom_headers = headers.is_a?(Hash) ? headers : {}
      default_headers.merge(custom_headers)
    end

    # Delivery methods
    def deliver(event_data, event_id = nil)
      event_id ||= SecureRandom.uuid
      delivery_id = SecureRandom.uuid

      delivery = webhook_deliveries.create!(
        delivery_id: delivery_id,
        event_id: event_id,
        status: "pending",
        attempt_number: 1,
        request_body: build_payload(event_data).to_json
      )

      # Enqueue webhook delivery job
      WebhookDeliveryJob.perform_async(delivery.id)
      delivery
    end

    def build_payload(event_data)
      template = payload_template_json

      if template.empty?
        # Default payload structure
        {
          event_type: event_type,
          app_id: app.id,
          timestamp: Time.current.iso8601,
          data: event_data
        }
      else
        # Use template with variable substitution
        substitute_variables(template, event_data)
      end
    end

    # Analytics methods
    def total_deliveries
      webhook_deliveries.count
    end

    def deliveries_last_24h
      webhook_deliveries.where("created_at > ?", 24.hours.ago).count
    end

    def success_rate
      total = webhook_deliveries.count
      return 0 if total.zero?

      successful = webhook_deliveries.where(status: "delivered").count
      ((successful.to_f / total) * 100).round(2)
    end

    def failure_rate
      100 - success_rate
    end

    def average_response_time
      webhook_deliveries.where.not(response_time_ms: nil)
                        .where(status: "delivered")
                        .average(:response_time_ms)&.to_f&.round(2) || 0
    end

    def pending_deliveries_count
      webhook_deliveries.where(status: "pending").count
    end

    def failed_deliveries_count
      webhook_deliveries.where(status: "failed").count
    end

    # Alias for backward compatibility
    def app_webhook_deliveries
      webhook_deliveries
    end

    private

    def normalize_fields
      self.http_method = http_method&.upcase
      self.url = url&.strip
      self.slug = slug&.downcase&.strip
      self.name = name&.strip
      self.event_type = event_type&.downcase&.strip
      self.content_type = content_type&.strip if content_type.present?
    end

    def generate_slug
      return unless name.present?

      base_slug = name.downcase.gsub(/[^a-z0-9\s]/, "").gsub(/\s+/, "_")
      counter = 0
      potential_slug = base_slug

      while app&.webhooks&.exists?(slug: potential_slug)
        counter += 1
        potential_slug = "#{base_slug}_#{counter}"
      end

      self.slug = potential_slug
    end

    def generate_secret_token
      self.secret_token = SecureRandom.hex(32)
    end

    def substitute_variables(template, event_data)
      # Simple variable substitution in JSON template
      json_string = template.to_json

      # Replace common variables
      json_string = json_string.gsub("{{app_id}}", app.id)
      json_string = json_string.gsub("{{event_type}}", event_type)
      json_string = json_string.gsub("{{timestamp}}", Time.current.iso8601)

      # Replace event data variables
      event_data.each do |key, value|
        json_string = json_string.gsub("{{#{key}}}", value.to_s)
      end

      JSON.parse(json_string)
    rescue JSON::ParserError
      # Fallback to default payload if template parsing fails
      {
        event_type: event_type,
        app_id: app.id,
        timestamp: Time.current.iso8601,
        data: event_data,
        error: "Template parsing failed, using default payload"
      }
    end

    def log_webhook_creation
      Rails.logger.info "AppWebhook created: #{id} - #{event_type} for app #{app.name}"
    end

    def log_webhook_updates
      Rails.logger.info "AppWebhook updated: #{id} - #{event_type}"
    end
  end
end

# Backward compatibility alias
AppWebhook = Marketplace::Webhook unless defined?(AppWebhook)
