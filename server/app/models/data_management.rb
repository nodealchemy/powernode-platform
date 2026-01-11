# frozen_string_literal: true

# DataManagement namespace for GDPR compliance and data management models
# Note: Named DataManagement to avoid conflict with Ruby 3.2's built-in Data class
# This module provides namespace for:
# - DataManagement::ExportRequest (GDPR Article 20 - Data Portability)
# - DataManagement::DeletionRequest (GDPR Article 17 - Right to Erasure)
# - DataManagement::RetentionPolicy (Data retention configuration)
module DataManagement
  def self.table_name_prefix
    "data_"
  end
end
