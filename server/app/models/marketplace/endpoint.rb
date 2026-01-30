# frozen_string_literal: true

module Marketplace
  class Endpoint < ApplicationRecord
    # Associations
    belongs_to :app, class_name: "Marketplace::Definition", foreign_key: "app_id"
    has_many :endpoint_calls, class_name: "Marketplace::EndpointCall", foreign_key: "app_endpoint_id", dependent: :destroy

    # Validations
    validates :name, presence: true, length: { minimum: 1, maximum: 255 }
    validates :slug, presence: true, length: { minimum: 1, maximum: 255 }
    validates :http_method, presence: true, inclusion: {
      in: %w[GET POST PUT PATCH DELETE HEAD OPTIONS],
      message: "must be a valid HTTP method"
    }
    validates :path, presence: true, length: { minimum: 1, maximum: 500 }
    validates :version, presence: true, length: { maximum: 20 }
    validates :slug, uniqueness: { scope: :app_id, message: "must be unique per app" }
    validates :path, uniqueness: {
      scope: [:app_id, :http_method],
      message: "and HTTP method combination must be unique per app"
    }

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :public_endpoints, -> { where(is_public: true) }
    scope :protected_endpoints, -> { where(requires_auth: true) }
    scope :by_method, ->(method) { where(http_method: method.to_s.upcase) }
    scope :by_version, ->(version) { where(version: version) }

    # Callbacks
    before_validation :normalize_fields
    before_validation :generate_slug, if: -> { slug.blank? }
    after_create :log_endpoint_creation
    after_update :log_endpoint_updates

    # Instance methods
    def active?
      is_active
    end

    def public?
      is_public
    end

    def requires_authentication?
      requires_auth
    end

    def full_path
      "/api/#{version}/apps/#{app.slug}#{path}"
    end

    def method_and_path
      "#{http_method} #{path}"
    end

    def request_schema_json
      return {} if request_schema.blank?
      JSON.parse(request_schema)
    rescue JSON::ParserError
      {}
    end

    def response_schema_json
      return {} if response_schema.blank?
      JSON.parse(response_schema)
    rescue JSON::ParserError
      {}
    end

    # Analytics methods
    def total_calls
      endpoint_calls.count
    end

    def calls_last_24h
      endpoint_calls.where("called_at > ?", 24.hours.ago).count
    end

    def average_response_time
      endpoint_calls.where.not(response_time_ms: nil).average(:response_time_ms)&.to_f&.round(2) || 0
    end

    def success_rate
      total = endpoint_calls.count
      return 0 if total.zero?

      successful = endpoint_calls.where(status_code: 200..299).count
      ((successful.to_f / total) * 100).round(2)
    end

    def error_rate
      100 - success_rate
    end

    # Alias for backward compatibility
    def app_endpoint_calls
      endpoint_calls
    end

    private

    def normalize_fields
      self.http_method = http_method&.upcase
      self.path = path&.strip
      self.path = "/#{path}" unless path&.start_with?("/")
      self.slug = slug&.downcase&.strip
      self.name = name&.strip
    end

    def generate_slug
      return unless name.present?

      base_slug = name.downcase.gsub(/[^a-z0-9\s]/, "").gsub(/\s+/, "_")
      counter = 0
      potential_slug = base_slug

      while app&.endpoints&.exists?(slug: potential_slug)
        counter += 1
        potential_slug = "#{base_slug}_#{counter}"
      end

      self.slug = potential_slug
    end

    def log_endpoint_creation
      Rails.logger.info "Marketplace::Endpoint created: #{id} - #{method_and_path} for app #{app.name}"
    end

    def log_endpoint_updates
      Rails.logger.info "Marketplace::Endpoint updated: #{id} - #{method_and_path}"
    end
  end
end
