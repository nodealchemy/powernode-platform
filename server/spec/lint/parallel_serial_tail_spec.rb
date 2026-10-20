# frozen_string_literal: true

require "spec_helper"

# IMP-7e1c8b0f4849 — scripts/parallel-serial-tail.txt lists the specs the parallel run keeps out of its
# balanced phase because they share state across processes. The list is only as good as its coverage, so
# this lint derives the dangerous shapes from the spec sources and fails when one is missing from it.
RSpec.describe "parallel run serial tail" do
  root = File.expand_path("../../..", __dir__)
  tail_path = File.join(root, "scripts", "parallel-serial-tail.txt")

  tail = File.readlines(tail_path, chomp: true)
             .map { |l| l.sub(/#.*/, "").strip }
             .reject(&:empty?)

  spec_files = Dir.glob(File.join(root, "{server,extensions/*/server}/spec/**/*_spec.rb"))
                  .reject { |f| f.include?("/spec/support/") || f.end_with?("/spec/lint/parallel_serial_tail_spec.rb") }
                  .map { |f| f.sub("#{root}/", "") }

  # Rule 1: DatabaseCleaner truncation, by tag or metadata.
  truncating = spec_files.select do |f|
    File.read(File.join(root, f)).match?(/truncation: true|type: :performance(?![a-z_])|,\s*:integration(?![a-z_])/)
  end

  # Rule 2: a literal, non-unique name under the checkout's tmp/storage/public/log. A line that derives the
  # path from an id, SecureRandom or a mktmpdir is unique per example and is not flagged.
  fixed_paths = spec_files.select do |f|
    File.foreach(File.join(root, f)).any? do |line|
      m = line.match(/Rails\.root\.join\(([^)]*)\)/)
      m && m[1].match?(/["'](tmp|storage|public|log)["'\/]/) && !line.match?(/SecureRandom|\.id\b|hex|uuid|_id\b|mktmpdir/i)
    end
  end

  # Rule 3: rewrites the real config/extensions_state.json that every process reads (a spec that points
  # ExtensionStateStore at a mktmpdir copy is fine; the real one is addressed from the project root).
  state_file_writers = spec_files.select do |f|
    src = File.read(File.join(root, f))
    src.include?('File.join(project_root, "config", "extensions_state.json")') &&
      src.match?(/File\.(write|delete)\(\s*state_file/)
  end

  it "lists only files that exist (entries under an uninitialised extension submodule are exempt: the wrapper skips them)" do
    missing = tail.reject do |f|
      next true if f.start_with?("extensions/") && Dir.glob(File.join(root, f.split("/")[0, 2].join("/"), "*")).empty?

      File.exist?(File.join(root, f))
    end
    expect(missing).to be_empty, "scripts/parallel-serial-tail.txt names files that do not exist: #{missing}"
  end

  it "lists each file once, repo-relative" do
    expect(tail.uniq.size).to eq(tail.size)
    expect(tail.grep(%r{\A/|\.\.})).to be_empty
  end

  it "covers every spec that uses a DatabaseCleaner truncation strategy" do
    expect(truncating - tail).to be_empty,
      "truncation specs missing from the serial tail: #{truncating - tail}"
  end

  it "covers every spec that writes a fixed-name path under Rails.root/tmp" do
    expect(fixed_paths - tail).to be_empty,
      "fixed-path specs missing from the serial tail: #{fixed_paths - tail}"
  end

  it "covers every spec that rewrites the shared config/extensions_state.json" do
    expect(state_file_writers - tail).to be_empty,
      "state-file specs missing from the serial tail: #{state_file_writers - tail}"
    expect(state_file_writers).not_to be_empty
  end

  it "found the files it is guarding (the rules are not vacuous)" do
    expect(truncating.size).to be >= 3
    expect(fixed_paths.size).to be >= 10
  end
end
