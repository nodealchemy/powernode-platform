# frozen_string_literal: true

# Backward compatibility alias for PluginSystem::Definition
require_relative "plugin_system/definition"
Plugin = PluginSystem::Definition unless defined?(Plugin)
