# frozen_string_literal: true

# Backward compatibility alias for Marketplace::EndpointCall
require_relative "marketplace/endpoint_call"
AppEndpointCall = Marketplace::EndpointCall unless defined?(AppEndpointCall)
