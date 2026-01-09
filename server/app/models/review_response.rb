# frozen_string_literal: true

# Backward compatibility alias for Review::Response
require_relative "review/response"
ReviewResponse = Review::Response unless defined?(ReviewResponse)
