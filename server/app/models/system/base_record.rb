# frozen_string_literal: true

module System
  # Base class for all System:: namespaced models
  # Provides common functionality and table naming conventions
  class BaseRecord < ApplicationRecord
    self.abstract_class = true

    # Override table name to use system_ prefix
    # e.g., System::Node -> system_nodes
    def self.table_name
      "system_#{name.demodulize.underscore.pluralize}"
    end
  end
end
