# frozen_string_literal: true

require "rails_helper"

# IMP-c11cae907ba3. db:schema:load runs assume_migrated_upto_version(header), so a
# header older than a migration on disk leaves that migration pending in every
# core-mode test DB even when its effect is already in the schema body. The
# header is hand-maintained (the post-migrate dump is disabled in
# config/initializers/schema_dump_isolation.rb), so it silently drifts.
#
# Static on purpose: comparing a DB built FROM schema.rb against schema.rb is
# circular. Private extensions are excluded; schema.rb is core + public only.
RSpec.describe "db/schema.rb version header" do
  let(:repo_root) { Rails.root.join("..") }
  let(:schema_version) do
    header = Rails.root.join("db/schema.rb").read[/define\(version:\s*([\d_]+)\)/, 1]
    raise "db/schema.rb has no ActiveRecord::Schema define(version: ...) header" if header.nil?

    header.delete("_").to_i
  end
  let(:migration_dirs) do
    [ Rails.root.join("db/migrate").to_s ] +
      Dir.glob(File.expand_path("extensions/*/server/db/migrate", repo_root)).reject { |d| d.include?("/private/") }
  end
  let(:disk_versions) do
    migration_dirs.flat_map { |dir| Dir.glob(File.join(dir, "[0-9]*_*.rb")) }
                  .map { |file| File.basename(file)[/\A\d+/].to_i }
  end

  it "finds the core migrations, so the comparison below cannot pass vacuously" do
    expect(disk_versions.length).to be > 50
  end

  it "is at least the newest core or public-extension migration version" do
    expect(schema_version).to be >= disk_versions.max,
      "schema.rb declares #{schema_version} but migration #{disk_versions.max} exists; " \
      "schema:load would leave it pending. Bump the define(version:) header after confirming " \
      "the migration's effect is in the schema body."
  end
end
