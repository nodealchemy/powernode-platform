# frozen_string_literal: true

# Backward compatibility alias for PluginSystem::Dependency
require_relative "plugin_system/dependency"
PluginDependency = PluginSystem::Dependency unless defined?(PluginDependency)
