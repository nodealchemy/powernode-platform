# frozen_string_literal: true

# Backward compatibility alias for Marketplace::Definition
require_relative "marketplace/definition"
App = Marketplace::Definition unless defined?(App)
