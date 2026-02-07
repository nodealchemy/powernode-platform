# frozen_string_literal: true

module Ai
  class MockResponse < ApplicationRecord
    self.table_name = "ai_mock_responses"

    # Override ActiveRecord's dangerous attribute check for model_name column
    class << self
      def dangerous_attribute_method?(method_name)
        return false if method_name == "model_name"

        super
      end
    end

    # Associations
    belongs_to :account
    belongs_to :sandbox, class_name: "Ai::Sandbox"
    belongs_to :created_by, class_name: "User", optional: true

    # Validations
    validates :name, presence: true
    validates :provider_type, presence: true
    validates :match_type, presence: true, inclusion: { in: %w[exact contains regex semantic always] }

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :by_provider, ->(provider) { where(provider_type: provider) }
    scope :by_model, ->(model) { where(model_name: model) }
    scope :ordered_by_priority, -> { order(priority: :desc) }

    # Methods
    def active?
      is_active
    end

    def activate!
      update!(is_active: true)
    end

    def deactivate!
      update!(is_active: false)
    end

    def matches?(request_data)
      case match_type
      when "always"
        true
      when "exact"
        exact_match?(request_data)
      when "contains"
        contains_match?(request_data)
      when "regex"
        regex_match?(request_data)
      when "semantic"
        semantic_match?(request_data)
      else
        false
      end
    end

    def get_response
      record_hit!

      # Simulate latency if configured
      sleep(latency_ms / 1000.0) if latency_ms.to_i > 0

      # Simulate errors based on error_rate
      if error_rate.to_f > 0 && rand < error_rate
        return {
          error: true,
          error_type: error_type || "mock_error",
          error_message: error_message || "Simulated error from mock response"
        }
      end

      response_data
    end

    def record_hit!
      increment!(:hit_count)
      update!(last_hit_at: Time.current)
    end

    private

    def exact_match?(request_data)
      return true if match_criteria.blank?

      match_criteria.all? do |key, expected|
        actual = extract_value(request_data, key)
        actual == expected
      end
    end

    def contains_match?(request_data)
      return true if match_criteria.blank?

      match_criteria.all? do |key, expected|
        actual = extract_value(request_data, key)
        actual.to_s.include?(expected.to_s)
      end
    end

    def regex_match?(request_data)
      return true if match_criteria.blank?

      match_criteria.all? do |key, pattern|
        actual = extract_value(request_data, key)
        actual.to_s.match?(Regexp.new(pattern.to_s))
      end
    rescue RegexpError
      false
    end

    def semantic_match?(request_data)
      # Semantic matching would require embedding comparison
      # For now, fall back to contains matching
      contains_match?(request_data)
    end

    def extract_value(data, field)
      return nil if data.blank? || field.blank?

      field.to_s.split(".").reduce(data) do |obj, key|
        break nil if obj.nil?

        if obj.is_a?(Hash)
          obj[key] || obj[key.to_sym]
        elsif obj.respond_to?(key)
          obj.send(key)
        else
          nil
        end
      end
    end
  end
end
