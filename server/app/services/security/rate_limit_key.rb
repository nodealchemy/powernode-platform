# frozen_string_literal: true

require "ipaddr"

module Security
  # The one place a Security::RateLimiter counter key is built, parsed or matched.
  #
  #   rate_limit:<category>[:account:<account_id>]:<subject>      subject: "ip:<addr>", "user:<id>", ...
  #
  # The writer (Security::RateLimiter) and the readers and admin tools
  # (RateLimiting::BaseService, the admin violations list) all go through here, so the shape the
  # writer produces and the shape the readers search for cannot drift apart. They had: the readers
  # looked for a four-part "rate_limit:<controller>:<action>:ip_<addr>" no writer ever produced.
  module RateLimitKey
    PREFIX = "rate_limit"
    ALL = "#{PREFIX}:*".freeze

    NUMERIC_ID = /\A\d+\z/
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    module_function

    def build(category:, key:, account_id: nil)
      parts = [ PREFIX, category ]
      parts << "account:#{account_id}" if account_id.present?
      parts << key
      parts.join(":")
    end

    # { category:, account_id:, subject: } or nil when the key is not in the writer's shape.
    def parse(redis_key)
      prefix, category, rest = redis_key.to_s.split(":", 3)
      return nil unless prefix == PREFIX && category.present? && rest.present?

      account_id = nil
      if rest.start_with?("account:")
        _, account_id, rest = rest.split(":", 3)
        return nil if account_id.blank? || rest.blank?
      end

      { category: category, account_id: account_id, subject: rest }
    end

    # The subject an admin identifier names, or nil when it is not one we accept. Strict on purpose:
    # the identifier is interpolated into a Redis glob.
    def subject_for(identifier)
      id = identifier.to_s
      if id.match?(NUMERIC_ID) || id.match?(UUID)
        "user:#{id}"
      elsif id.match?(/\A[\h:.]+\z/) && ip?(id)
        "ip:#{id}"
      end
    end

    # SCAN pattern for every counter of one identifier, whatever its category or account scope.
    # A superset of the real matches (callers filter on parse(...)[:subject]).
    def pattern_for(subject)
      "#{PREFIX}:*:#{subject}"
    end

    def ip?(value)
      IPAddr.new(value)
      true
    rescue IPAddr::Error
      false
    end
  end
end
