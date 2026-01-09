# frozen_string_literal: true

# Backward compatibility alias for Marketplace::Feature
require_relative "marketplace/feature"
AppFeature = Marketplace::Feature unless defined?(AppFeature)
