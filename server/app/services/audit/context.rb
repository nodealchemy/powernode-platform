# frozen_string_literal: true

module Audit
  # Audit::Context — thread-local scratch space for per-request audit
  # provenance (actor user, client IP, mission/correlation ids). Controllers
  # call `Audit::Context.with(...) { ... }` around the lifecycle action and
  # the auditable concerns read from `Audit::Context.current` to enrich each
  # AuditLog row with actor + correlation metadata.
  #
  # This avoids threading audit-only kwargs (ip_address, user, request_id,
  # mission_id, correlation_id, etc.) through every service call.
  #
  # Default value is an empty hash so callers can `dig` safely without nil
  # checks. Anything outside a `with` block sees the empty default.
  module Context
    THREAD_KEY = :__audit_context

    module_function

    # Returns the current audit context (a frozen Hash). Always non-nil.
    def current
      Thread.current[THREAD_KEY] || {}
    end

    # Sets the audit context for the duration of the block. Nested calls
    # merge with the outer context (inner keys win).
    def with(**fields)
      previous = Thread.current[THREAD_KEY] || {}
      Thread.current[THREAD_KEY] = previous.merge(fields.compact).freeze
      yield
    ensure
      Thread.current[THREAD_KEY] = previous
    end

    # Resets the context to empty. Primarily for tests.
    def reset!
      Thread.current[THREAD_KEY] = nil
    end
  end
end
