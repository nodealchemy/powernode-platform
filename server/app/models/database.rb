# frozen_string_literal: true

# Database namespace for database management models
# This module provides namespace for:
# - Database::Backup (Database backup records)
# - Database::Restore (Database restore operations)
module Database
  def self.table_name_prefix
    "database_"
  end
end
