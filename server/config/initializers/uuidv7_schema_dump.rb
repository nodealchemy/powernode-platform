# frozen_string_literal: true

# Make db/schema.rb self-bootstrapping for UUIDv7: PG16 has no native uuidv7(),
# and Rails' :ruby schema format does not dump SQL functions — so a `uuidv7()`
# column default in schema.rb would reference a function `db:schema:load` never
# creates. This SchemaDumper hook emits the function definition right after
# enable_extension and before the first create_table, so schema:load creates it
# in time. (The SetupUuidv7 migration covers the db:migrate-from-empty path.)
require "active_record/schema_dumper"

module Powernode
  module Uuidv7SchemaDump
    UUIDV7_FN_SQL = <<~'SQL'.gsub(/\s+/, " ").strip
      CREATE OR REPLACE FUNCTION uuidv7() RETURNS uuid AS $$
        SELECT encode(set_bit(set_bit(
          overlay(uuid_send(gen_random_uuid())
                  placing substring(int8send((extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3)
                  FROM 1 FOR 6),
          52, 1), 53, 1), 'hex')::uuid;
      $$ LANGUAGE sql VOLATILE;
    SQL

    def tables(stream)
      stream.puts "  # UUIDv7 primary-key default function (PG16 shim; native on PG18+ — self-skipping)."
      stream.puts %(  unless select_value("SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'uuidv7')"))
      stream.puts "    execute(#{UUIDV7_FN_SQL.inspect})"
      stream.puts "  end"
      stream.puts
      super
    end
  end
end

ActiveRecord::SchemaDumper.prepend(Powernode::Uuidv7SchemaDump)
