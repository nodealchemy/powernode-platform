# frozen_string_literal: true

class UpdateFileStorageProviderTypeConstraint < ActiveRecord::Migration[8.0]
  def up
    # Remove the old constraint
    execute <<-SQL
      ALTER TABLE file_storages
      DROP CONSTRAINT IF EXISTS file_storages_provider_type_check;
    SQL

    # Add the new constraint with nfs and smb
    execute <<-SQL
      ALTER TABLE file_storages
      ADD CONSTRAINT file_storages_provider_type_check
      CHECK (provider_type IN ('local', 's3', 'gcs', 'azure', 'nfs', 'smb', 'ftp', 'webdav', 'custom'));
    SQL
  end

  def down
    # Remove the new constraint
    execute <<-SQL
      ALTER TABLE file_storages
      DROP CONSTRAINT IF EXISTS file_storages_provider_type_check;
    SQL

    # Restore the old constraint without nfs and smb
    execute <<-SQL
      ALTER TABLE file_storages
      ADD CONSTRAINT file_storages_provider_type_check
      CHECK (provider_type IN ('local', 's3', 'gcs', 'azure', 'ftp', 'webdav', 'custom'));
    SQL
  end
end
