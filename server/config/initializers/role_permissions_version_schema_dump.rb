# frozen_string_literal: true

# Make db/schema.rb self-bootstrapping for the role-grant version trigger.
#
# Rails' :ruby schema format dumps tables, indexes and foreign keys — never
# functions or triggers. `roles.permissions_version` therefore dumps fine, but
# the trigger that BUMPS it would silently vanish from any database created with
# `db:schema:load` (which is how fresh installs and `db:test:prepare` build one).
# The counter would then sit at 0 forever and User#permission_names_cache_key
# would go back to being blind to role-grant changes — the IMP-95e4904258c8
# failure, reintroduced by a database-creation path rather than by an edit.
#
# Same arrangement, and same reason, as uuidv7_schema_dump.rb. The canonical copy
# of this SQL is db/migrate/20260901000000_add_permissions_version_to_roles.rb;
# the two are cross-referenced. Emitted AFTER the tables (super) because it
# references both role_permissions and roles.
require "active_record/schema_dumper"

module Powernode
  module RolePermissionsVersionSchemaDump
    STATEMENTS = [
      <<~'SQL'.strip,
        CREATE OR REPLACE FUNCTION bump_role_permissions_version() RETURNS trigger AS $$
        BEGIN
          IF (TG_OP = 'DELETE') THEN
            UPDATE roles SET permissions_version = permissions_version + 1 WHERE id = OLD.role_id;
            RETURN OLD;
          ELSIF (TG_OP = 'UPDATE') THEN
            UPDATE roles SET permissions_version = permissions_version + 1 WHERE id IN (NEW.role_id, OLD.role_id);
            RETURN NEW;
          ELSE
            UPDATE roles SET permissions_version = permissions_version + 1 WHERE id = NEW.role_id;
            RETURN NEW;
          END IF;
        END;
        $$ LANGUAGE plpgsql;
      SQL
      <<~'SQL'.strip,
        CREATE OR REPLACE FUNCTION bump_all_role_permissions_versions() RETURNS trigger AS $$
        BEGIN
          UPDATE roles SET permissions_version = permissions_version + 1;
          RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;
      SQL
      "DROP TRIGGER IF EXISTS role_permissions_version_bump ON role_permissions;",
      <<~'SQL'.strip,
        CREATE TRIGGER role_permissions_version_bump
        AFTER INSERT OR UPDATE OR DELETE ON role_permissions
        FOR EACH ROW EXECUTE FUNCTION bump_role_permissions_version();
      SQL
      "ALTER TABLE role_permissions ENABLE ALWAYS TRIGGER role_permissions_version_bump;",
      "DROP TRIGGER IF EXISTS role_permissions_version_bump_truncate ON role_permissions;",
      <<~'SQL'.strip,
        CREATE TRIGGER role_permissions_version_bump_truncate
        AFTER TRUNCATE ON role_permissions
        FOR EACH STATEMENT EXECUTE FUNCTION bump_all_role_permissions_versions();
      SQL
      "ALTER TABLE role_permissions ENABLE ALWAYS TRIGGER role_permissions_version_bump_truncate;"
    ].freeze

    def tables(stream)
      super
      stream.puts
      stream.puts "  # Role-grant version trigger (IMP-95e4904258c8): bumps roles.permissions_version"
      stream.puts "  # on every role_permissions write, so User#permission_names_cache_key can observe a"
      stream.puts "  # narrowing made by RAW SQL. Not dumpable by the :ruby schema format — see"
      stream.puts "  # config/initializers/role_permissions_version_schema_dump.rb."
      # NO GUARD. A conditional here would SILENTLY SKIP on a false premise and
      # leave permissions_version frozen at 0 — which is the vulnerability this
      # exists to close, restored with no error anywhere. Both objects are
      # created earlier in this same dump, so a failure to find them is a real
      # defect and must raise. (This is why it differs from the uuidv7 guard,
      # whose skip condition — "the function already exists" — is safe.)
      STATEMENTS.each { |sql| stream.puts "  execute(#{sql.inspect})" }
    end
  end
end

ActiveRecord::SchemaDumper.prepend(Powernode::RolePermissionsVersionSchemaDump)
