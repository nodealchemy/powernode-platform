# frozen_string_literal: true

# Backward compatibility alias for Marketplace::Endpoint
require_relative "marketplace/endpoint"
AppEndpoint = Marketplace::Endpoint unless defined?(AppEndpoint)
