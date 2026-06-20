# frozen_string_literal: true

# Keep PRIVATE-extension tables out of the committed public db/schema.rb.
#
# A table owned by a private extension (extensions/private/*) is excluded from
# EVERY schema dump — including the automatic dump after `db:migrate` in dev/test
# (`dump_schema_after_migration` defaults true there) — so a maintainer checkout
# that has the private extensions on disk can never re-leak their schema into the
# public repo. This is the schema-layer twin of the public/private Gemfile split:
# `Gemfile.private` adds private *gems*; this keeps private *tables* out of the
# public schema. Public-extension tables (system_/marketing_/supply_chain_) stay
# in db/schema.rb, exactly as public extensions stay in the public Gemfile.
#
# Generic, zero-edit-per-extension: the exclusion set is the union of
# `owned_prefixes` declared by PRIVATE extensions, resolved at dump time from the
# registry (so it is correct regardless of initializer/registration ordering).
require "active_record/schema_dumper"

module Powernode
  module PrivateSchemaIsolation
    # `ignored?` is the per-table chokepoint AR's dumper consults before emitting a
    # table (activerecord schema_dumper.rb). Defer to the stock matcher first, then
    # exclude any table owned by a loaded private extension.
    def ignored?(table_name)
      return true if super

      defined?(Powernode::ExtensionRegistry) &&
        Powernode::ExtensionRegistry.table_private?(table_name)
    end
  end
end

ActiveRecord::SchemaDumper.prepend(Powernode::PrivateSchemaIsolation)

# The committed public db/schema.rb is generated in CORE mode (no private extensions
# loaded), where the private FKs the business baseline adds to core tables do NOT exist —
# so a core-mode dump is leak-free. A FULL-mode post-migrate auto-dump, however, re-emits
# those FKs (SchemaDumper dumps foreign keys even to ignored tables) and would re-leak
# business_/trading_ names. So disable the post-migrate auto-dump everywhere; regenerate
# schema.rb explicitly via a CORE-mode `bin/rails db:schema:dump`. (CI leak guard backstops.)
Rails.application.config.after_initialize do
  ActiveRecord.dump_schema_after_migration = false
end
