# frozen_string_literal: true

# Backward compatibility alias for PluginSystem::Review
require_relative "plugin_system/review"
PluginReview = PluginSystem::Review unless defined?(PluginReview)
