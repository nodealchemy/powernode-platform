# frozen_string_literal: true

# Monitoring namespace for service health and circuit breaker models
# This module provides namespace for:
# - Monitoring::CircuitBreaker (Service health monitoring)
# - Monitoring::CircuitBreakerEvent (Circuit breaker state events)
#
# NOTE: Unlike other namespaces, Monitoring does NOT use table_name_prefix
# because tables are named `circuit_breakers` not `monitoring_circuit_breakers`.
# Models in this namespace must specify explicit `self.table_name`.
module Monitoring
end

