# frozen_string_literal: true

# Adds cryptographic hash chain for immutable audit logs
# SOC 2 / PCI DSS Compliance requirement
class AddImmutabilityToAuditLogs < ActiveRecord::Migration[8.0]
  def change
    # Add hash chain columns for immutability verification
    add_column :audit_logs, :integrity_hash, :string, null: true
    add_column :audit_logs, :previous_hash, :string, null: true
    add_column :audit_logs, :sequence_number, :bigint, null: true
    add_column :audit_logs, :chain_verified_at, :datetime, null: true

    # Index for efficient chain verification queries
    add_index :audit_logs, :sequence_number, unique: true, where: 'sequence_number IS NOT NULL'
    add_index :audit_logs, :integrity_hash, unique: true, where: 'integrity_hash IS NOT NULL'
    add_index :audit_logs, :chain_verified_at

    # Prevent modifications to audit logs at database level
    # This creates a trigger that blocks UPDATE and DELETE operations
    reversible do |dir|
      dir.up do
        execute <<-SQL
          -- Create function to block modifications
          CREATE OR REPLACE FUNCTION prevent_audit_log_modification()
          RETURNS TRIGGER AS $$
          BEGIN
            -- Allow updates to chain_verified_at only (for verification tracking)
            IF TG_OP = 'UPDATE' THEN
              IF (OLD.action != NEW.action OR
                  OLD.details IS DISTINCT FROM NEW.details OR
                  OLD.resource_type IS DISTINCT FROM NEW.resource_type OR
                  OLD.resource_id IS DISTINCT FROM NEW.resource_id OR
                  OLD.user_id IS DISTINCT FROM NEW.user_id OR
                  OLD.ip_address IS DISTINCT FROM NEW.ip_address OR
                  OLD.user_agent IS DISTINCT FROM NEW.user_agent OR
                  OLD.integrity_hash IS DISTINCT FROM NEW.integrity_hash OR
                  OLD.previous_hash IS DISTINCT FROM NEW.previous_hash OR
                  OLD.sequence_number IS DISTINCT FROM NEW.sequence_number) THEN
                RAISE EXCEPTION 'Audit logs are immutable and cannot be modified';
              END IF;
              RETURN NEW;
            END IF;

            -- Block all deletes
            IF TG_OP = 'DELETE' THEN
              RAISE EXCEPTION 'Audit logs are immutable and cannot be deleted';
            END IF;

            RETURN NULL;
          END;
          $$ LANGUAGE plpgsql;

          -- Create trigger to enforce immutability
          CREATE TRIGGER enforce_audit_log_immutability
            BEFORE UPDATE OR DELETE ON audit_logs
            FOR EACH ROW
            EXECUTE FUNCTION prevent_audit_log_modification();
        SQL
      end

      dir.down do
        execute <<-SQL
          DROP TRIGGER IF EXISTS enforce_audit_log_immutability ON audit_logs;
          DROP FUNCTION IF EXISTS prevent_audit_log_modification();
        SQL
      end
    end
  end
end
