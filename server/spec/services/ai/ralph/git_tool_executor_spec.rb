# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Ralph::GitToolExecutor, type: :service do
  let(:git_client) { double("git_client") }

  # Build an executor without the heavy initialize (which needs a ralph_loop with a
  # repository + git credential). We only exercise handle_write_file's create/update
  # bookkeeping, so set just the ivars it touches.
  subject(:executor) do
    described_class.allocate.tap do |e|
      e.instance_variable_set(:@git_client, git_client)
      e.instance_variable_set(:@owner, "acme")
      e.instance_variable_set(:@repo, "widgets")
      e.instance_variable_set(:@branch, "main")
      e.instance_variable_set(:@file_changes, [])
    end
  end

  let(:write_result) { { success: true, content: { "commit" => { "sha" => "abc123" } } } }

  describe "#execute write_file operation labelling" do
    # Regression: the create-vs-update DECISION uses `existing && existing[:sha]`, but the
    # recorded operation used `existing ? :updated : :created`. A truthy existing hash
    # WITHOUT :sha (directory entry / blob-without-sha / oversized response) → create_file
    # is called but the change ledger mislabels it :updated.
    it "records :created when the existing entry is truthy but has no :sha" do
      allow(git_client).to receive(:get_file_content).and_return({ size: 0 }) # truthy, no :sha
      expect(git_client).to receive(:create_file).and_return(write_result)
      expect(git_client).not_to receive(:update_file)

      result = executor.execute("write_file", { path: "new_file.rb", content: "x" })

      expect(result[:operation]).to eq(:created)
      expect(executor.file_changes.last[:operation]).to eq(:created)
    end

    it "records :created when the file does not exist (nil)" do
      allow(git_client).to receive(:get_file_content).and_return(nil)
      allow(git_client).to receive(:create_file).and_return(write_result)

      result = executor.execute("write_file", { path: "new_file.rb", content: "x" })
      expect(result[:operation]).to eq(:created)
    end

    it "records :updated when the existing file has a :sha" do
      allow(git_client).to receive(:get_file_content).and_return({ sha: "deadbeef" })
      expect(git_client).to receive(:update_file).and_return(write_result)
      expect(git_client).not_to receive(:create_file)

      result = executor.execute("write_file", { path: "f.rb", content: "x" })
      expect(result[:operation]).to eq(:updated)
    end
  end

  # G3 follow-up: assemble a bounded, real unified diff for the maker/checker.
  describe "#unified_diff" do
    it "assembles a unified diff from the commit's per-file patches, adding headers" do
      allow(git_client).to receive(:get_commit_diff).with("acme", "widgets", "abc123").and_return(
        files: [
          { filename: "app/x.rb", raw_patch: "@@ -1 +1,2 @@\n line\n+added\n" },
          { filename: "app/y.rb", raw_patch: "@@ -0,0 +1 @@\n+new\n" }
        ]
      )

      diff = executor.unified_diff("abc123")

      expect(diff).to include("diff --git a/app/x.rb b/app/x.rb")
      expect(diff).to include("+added")
      expect(diff).to include("diff --git a/app/y.rb b/app/y.rb")
      expect(diff).to include("+new")
    end

    it "preserves an already-headed patch without double-prefixing" do
      allow(git_client).to receive(:get_commit_diff).and_return(
        files: [{ filename: "app/x.rb", raw_patch: "diff --git a/app/x.rb b/app/x.rb\n@@ -1 +1 @@\n+z\n" }]
      )

      diff = executor.unified_diff("abc123")

      expect(diff.scan("diff --git").size).to eq(1)
    end

    it "caps an oversized diff and appends a truncation marker" do
      huge = "+#{'a' * (Ai::Ralph::GitToolExecutor::MAX_DIFF_BYTES + 5_000)}\n"
      allow(git_client).to receive(:get_commit_diff).and_return(
        files: [{ filename: "big.txt", raw_patch: huge }]
      )

      diff = executor.unified_diff("abc123")

      expect(diff).to include("[diff truncated at #{Ai::Ralph::GitToolExecutor::MAX_DIFF_BYTES} bytes]")
      # Body stays bounded to the cap (plus the short marker line).
      expect(diff.bytesize).to be <= Ai::Ralph::GitToolExecutor::MAX_DIFF_BYTES + 100
    end

    it "returns nil when there is no commit sha" do
      expect(executor.unified_diff(nil)).to be_nil
    end

    it "returns nil when the provider has no files in the diff" do
      allow(git_client).to receive(:get_commit_diff).and_return(files: [])
      expect(executor.unified_diff("abc123")).to be_nil
    end

    it "returns nil (best-effort) when the diff call raises" do
      allow(git_client).to receive(:get_commit_diff).and_raise(StandardError, "boom")
      expect(executor.unified_diff("abc123")).to be_nil
    end
  end
end
