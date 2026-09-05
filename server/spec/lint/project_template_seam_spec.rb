# frozen_string_literal: true

require "spec_helper"

# APO increment `app-4-project-noun` — the guard on the template seam.
#
# `Ai::Project` holds a reference to the node template it is composed from, and
# that template is owned by an EXTENSION. Core never depends on an extension,
# so the reference is POLYMORPHIC: `template_type` carries the class name as
# DATA. The obvious "simplification" a future reader will reach for is to
# replace it with `class_name: "<Extension>::NodeTemplate"` — which compiles,
# passes every functional spec on a checkout where that extension is present,
# and breaks core mode silently.
#
# Neither existing control catches that. `core-purity-check.sh` and its
# `pattern-validation.sh` mirror derive their forbidden names from
# `extensions/private/*` only, and `spec/lint/extension_namespace_ratchet_spec.rb`
# scans `server/spec`, not `server/app`. A blanket "core names no extension"
# assertion is not available either: core already carries ~76 such references
# (guarded `defined?` calls, executor-class strings, prose), so the ratchet has
# to be file-scoped. These are the files this increment introduced, and their
# baseline is ZERO.
#
# CONTAINMENT + PRESENCE, not absence alone. An absence assertion over a file
# that has been renamed or emptied passes while asserting nothing, so each file
# must exist AND still carry the seam before its absence claim counts. The
# extension namespaces are derived from the directory listing rather than
# spelled here, so a new extension is covered the day it lands and this file
# never has to name one.
RSpec.describe "Ai::Project template seam — core names no extension" do
  repo_root = File.expand_path("../../..", __dir__)

  # Files this increment added to core. Each must exist; an entry that names
  # nothing is a stale ratchet, which is why that is asserted first.
  guarded_files = [
    "server/app/models/ai/project.rb",
    "server/app/services/ai/tools/project_tool.rb",
    "server/db/migrate/20260905062000_create_ai_projects.rb"
  ].freeze

  # Every extension namespace on this checkout, public and private, derived the
  # way core-purity-check.sh derives its own: from the directory names. Never
  # spelled, so this file can be published with core and still cover an
  # extension it has never heard of.
  extension_namespaces =
    Dir.glob(File.join(repo_root, "extensions", "*"))
       .select { |path| File.directory?(path) }
       .reject { |path| File.basename(path) == "private" }
       .concat(Dir.glob(File.join(repo_root, "extensions", "private", "*")).select { |p| File.directory?(p) })
       .map { |path| File.basename(path).split(/[-_]/).map(&:capitalize).join }
       .uniq
       .freeze

  it "derives at least one extension namespace to check against" do
    # Without this the absence assertions below would be vacuous on a checkout
    # where the glob found nothing.
    expect(extension_namespaces).not_to be_empty
  end

  guarded_files.each do |rel|
    context rel do
      let(:path) { File.join(repo_root, rel) }

      it "exists" do
        expect(File.file?(path)).to be(true),
          "#{rel} is missing — this ratchet guards a file that is no longer there"
      end

      it "names no extension namespace" do
        body = File.read(path)
        offenders = extension_namespaces.select { |ns| body.match?(/\b#{Regexp.escape(ns)}::/) }

        expect(offenders).to be_empty,
          "#{rel} names extension namespace(s) #{offenders.join(', ')} — core must reach an " \
          "extension through a generic seam (here: the polymorphic template_type/template_id pair)"
      end
    end
  end

  it "keeps the template reference POLYMORPHIC on the model" do
    body = File.read(File.join(repo_root, "server/app/models/ai/project.rb"))

    expect(body).to include("belongs_to :template, polymorphic: true")
  end

  it "keeps the template columns generic in the migration" do
    body = File.read(File.join(repo_root, "server/db/migrate/20260905062000_create_ai_projects.rb"))

    expect(body).to match(/t\.string\s+:template_type/)
    expect(body).to match(/t\.uuid\s+:template_id/)
    # A real foreign key onto an extension table would be the same coupling in
    # DDL form, and it would fail to migrate wherever that extension is absent.
    expect(body).not_to match(/add_foreign_key/)
  end
end
