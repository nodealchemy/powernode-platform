# frozen_string_literal: true

# Backward compatibility alias for Review::AggregationCache
require_relative "review/aggregation_cache"
ReviewAggregationCache = Review::AggregationCache unless defined?(ReviewAggregationCache)
