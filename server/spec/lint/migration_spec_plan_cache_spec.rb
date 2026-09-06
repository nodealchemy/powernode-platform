# frozen_string_literal: true

require "rails_helper"

# A spec that executes REAL DDL inside an example poisons PostgreSQL's
# per-connection prepared-statement plan cache for every LATER spec in the same
# process that touches the altered table.
#
# The example's transaction rolls the DDL back, so the schema is restored and
# the file itself passes -- which is exactly what makes this hard to see. What
# survives the rollback is the plan cache, still holding plans built against
# the shapes seen mid-example, and the next `reload` of that model raises
#
#   PG::FeatureNotSupported: ERROR: cached plan must not change result type
#
# The failures land in OTHER files, attributed to code that is not broken.
# Observed for real: sharding the extension suite put
# add_match_method_to_system_cve_exposures_spec.rb in the same process as the
# CVE model and orchestration specs, and 16 examples failed with that error --
# none of them in the file that caused it (run 1781, shard 3).
#
# The fix is one line, `ActiveRecord::Base.connection.clear_cache!` in an
# after(:context) hook, which runs AFTER the per-example transaction rolls
# back. This guard exists because the failure mode is silent, remote from its
# cause, and only appears once file ordering happens to put a victim after the
# culprit -- so it can lie dormant through many green runs.
#
# Scope note: the glob reaches any mounted extension's spec tree generically
# and names no extension, so core stays free of extension dependencies.
RSpec.describe "migration specs that run real DDL drop the plan cache" do
  ROOT = Rails.root.join("..").freeze

  # Executes a migration for real (rather than merely describing one).
  EXECUTES_MIGRATION = /
    migration\.(up|down)\b
    | \.connection\.(add|remove|change)_column\b
    | connection\.execute\(\s*["'][^"']*\bALTER\s+TABLE\b
  /xi

  # Changes a table's RESULT TYPE -- the property that invalidates a cached
  # plan. An index or a data-only backfill does not.
  #
  # This is matched against the MIGRATION the spec loads, not against the spec
  # itself. A migration spec names the migration and calls up/down on it; the
  # add_column lives in the migration file. An earlier draft of this guard
  # scanned the spec text for add_column and would therefore have missed the
  # very file that motivated it -- caught by mutating the real offender and
  # watching this lint stay green.
  CHANGES_RESULT_TYPE = /^\s*(add_column|remove_column|change_column)\b/

  DROPS_PLAN_CACHE = /clear_cache!/

  # The migration files a spec pulls in, from either spelling of the require:
  # a Rails.root.join(...) path or a plain relative require.
  MIGRATION_REQUIRE = %r{["']([^"']*db/migrate/[^"']+\.rb)["']}

  def spec_files
    core = Dir[Rails.root.join("spec/**/*_spec.rb").to_s]
    # Generic: every mounted extension, none named.
    ext  = Dir[ROOT.join("extensions/*/server/spec/**/*_spec.rb").to_s]
    (core + ext).sort
  end

  def migrations_loaded_by(source)
    source.scan(MIGRATION_REQUIRE).flatten
  end

  def alters_a_column?(source)
    migrations_loaded_by(source).any? do |fragment|
      matches = Dir[ROOT.join("**", File.basename(fragment)).to_s]
      matches.any? { |m| m.include?("db/migrate") && File.read(m).match?(CHANGES_RESULT_TYPE) }
    end
  end

  it "has no spec that alters a table's shape without dropping the cache afterwards" do
    offenders = spec_files.select do |path|
      source = File.read(path)
      source.match?(EXECUTES_MIGRATION) &&
        !source.match?(DROPS_PLAN_CACHE) &&
        alters_a_column?(source)
    end

    relative = offenders.map { |p| p.sub("#{ROOT}/", "") }

    expect(relative).to be_empty, <<~MSG
      These specs execute DDL that changes a table's result type but never drop
      the connection's prepared-statement plan cache:

        #{relative.join("\n  ")}

      Add to the example group:

        after(:context) { ActiveRecord::Base.connection.clear_cache! }

      after(:context) is the right hook because it runs AFTER the per-example
      transaction rolls the DDL back. Without it the next spec in the SAME
      process that reloads a row from that table fails with
      "cached plan must not change result type" -- in a different file, blamed
      on code that is not broken.
    MSG
  end

  # The guard is only worth having if it can actually see an offender. A
  # detector that matches nothing passes forever and protects nothing -- and
  # the first draft of this one did exactly that, so these are not decoration.
  it "sees a spec that loads a column-altering migration and does not clear" do
    source = <<~RUBY_SRC
      require Rails.root.join("../extensions/system/server/db/migrate/20260903150000_add_match_method_to_system_cve_exposures.rb")
      migration.suppress_messages { migration.down }
    RUBY_SRC

    expect(source).to match(EXECUTES_MIGRATION)
    expect(source).not_to match(DROPS_PLAN_CACHE)
    expect(alters_a_column?(source)).to be(true)
  end

  it "clears that same spec once the cache drop is present" do
    source = <<~RUBY_SRC
      require Rails.root.join("../extensions/system/server/db/migrate/20260903150000_add_match_method_to_system_cve_exposures.rb")
      migration.suppress_messages { migration.down }
      after(:context) { ActiveRecord::Base.connection.clear_cache! }
    RUBY_SRC

    expect(source).to match(DROPS_PLAN_CACHE)
  end

  # ...and only worth having if it does NOT fire on the shapes that look
  # similar and are harmless: a spec that merely quotes DDL in a fixture string
  # without executing it, and a migration that runs but alters no column.
  it "ignores a spec that only describes DDL without executing it" do
    described = %(source = "def change\\n add_column :widgets, :x, :string\\nend")

    expect(described).not_to match(EXECUTES_MIGRATION)
  end

  it "ignores a data-only migration that executes but alters no column" do
    data_only = "migration.suppress_messages { migration.up }"

    expect(data_only).to match(EXECUTES_MIGRATION)
    expect(alters_a_column?(data_only)).to be(false)
  end
end
