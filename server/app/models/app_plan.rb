# frozen_string_literal: true

# Backward compatibility alias for Marketplace::Plan
require_relative "marketplace/plan"
AppPlan = Marketplace::Plan unless defined?(AppPlan)
