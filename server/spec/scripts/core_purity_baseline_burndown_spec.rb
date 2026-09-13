# frozen_string_literal: true

require "spec_helper"

# IMP-acef5b5861c0 — the core-purity baseline is burned down, never grown.
#
# .claude/hooks/core-purity-baseline.txt grandfathers core -> public-extension and
# extension -> other-extension references that predate gate #9. Each entry is an
# Extension Isolation violation tolerated only because it is old, and the operator
# ruled (2026-09-08) that there is no legacy support: burn it down entry by entry
# through generic seams, the count may only decrease, delete the file when empty.
#
# The ratchet below is that rule made mechanical. Lower it in the same commit that
# removes entries; never raise it.
RSpec.describe ".claude/hooks/core-purity-baseline.txt" do
  let(:repo_root) { File.expand_path("../../..", __dir__) }
  let(:baseline) { File.join(repo_root, ".claude/hooks/core-purity-baseline.txt") }
  let(:entries) do
    File.exist?(baseline) ? File.readlines(baseline, chomp: true).reject { |l| l.strip.empty? || l.start_with?("#") } : []
  end

  # The highest the committed entry count may be. Lower it as entries go.
  let(:ceiling) { 59 }

  it "holds no more entries than the ratchet allows" do
    expect(entries.size).to be <= ceiling,
                            "baseline has #{entries.size} entries, ceiling is #{ceiling}; entries may only be removed"
  end

  # Factories for an extension's models belong to that extension: rails_helper
  # loads every active extension's spec/factories and lets them override a core
  # factory of the same name, so a core copy is at best a shadowed duplicate.
  it "grandfathers no core factory" do
    offenders = entries.grep(%r{\Aserver/spec/factories/})
    expect(offenders).to be_empty, "core factories naming an extension: #{offenders.inspect}"
  end

  # An entry inside an extension can only be checked where that extension is
  # checked out; a clone without submodules has no tree to look in.
  it "names only files that still exist" do
    paths = entries.map { |e| e.split("|").first }
    checkable = paths.reject do |path|
      ext = path[%r{\Aextensions/[^/]+}]
      ext && !Dir.exist?(File.join(repo_root, ext, "server"))
    end
    missing = checkable.reject { |path| File.exist?(File.join(repo_root, path)) }
    expect(missing).to be_empty, "stale baseline entries: #{missing.inspect}"
  end
end
