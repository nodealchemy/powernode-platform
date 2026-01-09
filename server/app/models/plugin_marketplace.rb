# frozen_string_literal: true

# Backward compatibility alias for PluginSystem::Marketplace
require_relative "plugin_system/marketplace"
PluginMarketplace = PluginSystem::Marketplace unless defined?(PluginMarketplace)
