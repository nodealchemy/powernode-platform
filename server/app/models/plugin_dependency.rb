# frozen_string_literal: true

# Plugin Dependency Model
# Tracks dependencies between plugins
class PluginDependency < ApplicationRecord
  belongs_to :plugin

  # Validations
  validates :dependency_plugin_id, presence: true
  validates :plugin_id, uniqueness: { scope: :dependency_plugin_id }

  # Scopes
  scope :required, -> { where(is_required: true) }
  scope :optional, -> { where(is_required: false) }

  # Check if dependency is satisfied
  def satisfied?(account)
    dependency = Plugin.find_by(plugin_id: dependency_plugin_id, account: account)
    return false if dependency.nil?

    return true if version_constraint.blank?

    Gem::Requirement.new(version_constraint).satisfied_by?(dependency.version_number)
  end

  # Get dependency plugin
  def dependency_plugin(account)
    Plugin.find_by(plugin_id: dependency_plugin_id, account: account)
  end
end
