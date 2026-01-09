# frozen_string_literal: true

# Backward compatibility alias for Marketplace::Review
require_relative "marketplace/review"
AppReview = Marketplace::Review unless defined?(AppReview)
