# frozen_string_literal: true

# UUIDv7 primary-key default for the whole platform (PG16 has no native uuidv7()).
# Created before any baseline so create_table's `default: -> { "uuidv7()" }` resolves.
class SetupUuidv7 < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")
    # PG18+ ships uuidv7() natively — only define the shim when it is absent (forward-compatible).
    return if connection.select_value("SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'uuidv7')")
    execute(<<~SQL)
      CREATE OR REPLACE FUNCTION uuidv7() RETURNS uuid AS $$
        SELECT encode(
          set_bit(set_bit(
            overlay(uuid_send(gen_random_uuid())
                    placing substring(int8send((extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3)
                    FROM 1 FOR 6),
            52, 1), 53, 1), 'hex')::uuid;
      $$ LANGUAGE sql VOLATILE;
    SQL
  end

  def down
    execute "DROP FUNCTION IF EXISTS uuidv7();"
  end
end
