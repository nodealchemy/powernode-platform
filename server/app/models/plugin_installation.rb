# frozen_string_literal: true

# Backward compatibility alias for PluginSystem::Installation
require_relative "plugin_system/installation"
PluginInstallation = PluginSystem::Installation unless defined?(PluginInstallation)
