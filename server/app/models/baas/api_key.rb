# frozen_string_literal: true

module BaaS
  class ApiKey < ApplicationRecord
    self.table_name = "baas_api_keys"

    # Associations
    belongs_to :baas_tenant, class_name: "BaaS::Tenant"

    # Validations
    validates :name, presence: true
    validates :key_prefix, presence: true
    validates :key_hash, presence: true, uniqueness: true
    validates :key_type, presence: true, inclusion: { in: %w[secret publishable restricted] }
    validates :environment, presence: true, inclusion: { in: %w[development staging production] }
    validates :status, presence: true, inclusion: { in: %w[active revoked expired] }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :for_environment, ->(env) { where(environment: env) }
    scope :secret_keys, -> { where(key_type: "secret") }
    scope :publishable_keys, -> { where(key_type: "publishable") }

    # Class methods
    class << self
      def generate_key(type: "secret", environment: "production")
        prefix = case type
        when "secret" then "sk"
        when "publishable" then "pk"
        when "restricted" then "rk"
        else "sk"
        end

        env_prefix = case environment
        when "production" then "live"
        when "staging" then "stag"
        else "test"
        end

        random_part = SecureRandom.hex(24)
        "#{prefix}_#{env_prefix}_#{random_part}"
      end

      def hash_key(key)
        Digest::SHA256.hexdigest(key)
      end

      def find_by_key(key)
        return nil if key.blank?
        key_hash = hash_key(key)
        find_by(key_hash: key_hash, status: "active")
      end
    end

    # Instance methods
    def active?
      status == "active" && !expired?
    end

    def revoked?
      status == "revoked"
    end

    def expired?
      expires_at.present? && expires_at < Time.current
    end

    def revoke!
      update!(status: "revoked")
    end

    def check_expiration!
      if expired? && status == "active"
        update!(status: "expired")
      end
    end

    def record_usage!
      increment!(:total_requests)
      update!(last_used_at: Time.current)
    end

    def has_scope?(scope)
      scopes.include?(scope) || scopes.include?("*")
    end

    def within_rate_limit?(requests_in_window, window_type: :minute)
      limit = case window_type
      when :minute then rate_limit_per_minute
      when :day then rate_limit_per_day
      else rate_limit_per_minute
      end
      requests_in_window < limit
    end

    def summary
      {
        id: id,
        name: name,
        key_prefix: key_prefix,
        key_type: key_type,
        environment: environment,
        status: status,
        scopes: scopes,
        total_requests: total_requests,
        last_used_at: last_used_at,
        expires_at: expires_at,
        created_at: created_at
      }
    end
  end
end
