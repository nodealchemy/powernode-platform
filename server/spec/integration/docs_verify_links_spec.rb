# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "fileutils"
require "shellwords"

# IMP-01a08a0f — the ONE hard gate in the docs workflow was red on every run.
#
# .gitea/workflows/docs.yml runs check-links.sh with no continue-on-error
# ("HARD gate: broken markdown links fail the build"); every sibling check is
# advisory. It reported 4 broken links, all resolving to
# docs/reference/auto/todo.md and .../learnings.md — files that are
# DELIBERATELY gitignored (commit 0bbe16e63, "split auto-gen tracking policy —
# mcp-tools tracked, DB-backed not") and that the workflow never generates,
# since it is a plain checkout with no build step before the gate.
#
# So the only two outcomes were "always red" or, with the [docs-skip-verify]
# marker, "verification skipped entirely". Neither is a gate. The references
# themselves are CORRECT for a deployed tree — CLAUDE.md legitimately points
# operators at the generated todo and learnings; what was missing is any notion
# of "generated, intentionally untracked".
#
# THE ORACLE IS A GREEN BASELINE PLUS A RED ON SOMETHING NEW. Asserting only
# "exit 0 today" would pass against a checker that can no longer fail — the
# same defect with the sign flipped — so the sandbox examples drive the real
# script and prove a genuinely dead link still reds it.
RSpec.describe "docs/.verify/check-links.sh", type: :integration do
  let(:repo_root) { Rails.root.join("..").cleanpath }
  let(:script) { repo_root.join("docs/.verify/check-links.sh") }

  it "is GREEN on this repository — the baseline a new broken link can disturb" do
    out = `bash #{Shellwords.escape(script.to_s)} 2>&1`
    expect($?.exitstatus).to eq(0), "check-links.sh is red on a clean tree:\n#{out}"
  end

  it "still names the generated targets rather than hiding them" do
    out = `bash #{Shellwords.escape(script.to_s)} 2>&1`
    expect(out).to match(%r{docs/reference/auto/(todo|learnings)\.md})
  end

  # --- sandbox: a throwaway git repo, so links and .gitignore are ours ---

  # `gitignored:` becomes the sandbox .gitignore. Returns [status, output].
  def run_in_sandbox(doc_body:, gitignored: [], create: [])
    Dir.mktmpdir("links-check") do |root|
      verify = File.join(root, "docs", ".verify")
      FileUtils.mkdir_p(verify)
      FileUtils.cp(script.to_s, File.join(verify, "check-links.sh"))

      File.write(File.join(root, ".gitignore"), gitignored.join("\n") + "\n")
      File.write(File.join(root, "docs", "guide.md"), doc_body)
      create.each do |rel|
        FileUtils.mkdir_p(File.dirname(File.join(root, rel)))
        File.write(File.join(root, rel), "x\n")
      end

      # A real git repo: the script asks git whether a target is ignored.
      system("git", "-C", root, "init", "-q", out: File::NULL, err: File::NULL)
      system("git", "-C", root, "add", "-A", out: File::NULL, err: File::NULL)

      out = `bash #{Shellwords.escape(File.join(verify, 'check-links.sh'))} 2>&1`
      [ $?.exitstatus, out ]
    end
  end

  it "does not fail on a missing target the repo deliberately does not track" do
    status, out = run_in_sandbox(
      doc_body: "See [the todo](reference/auto/todo.md).\n",
      gitignored: [ "docs/reference/auto/todo.md" ]
    )
    expect(status).to eq(0), out
  end

  # THE POINT OF THE WHOLE CHANGE: a genuinely dead link is visible again.
  it "still fails on a missing target that is NOT gitignored" do
    status, out = run_in_sandbox(
      doc_body: "See [a dead doc](reference/does-not-exist.md).\n",
      gitignored: []
    )
    expect(status).to eq(1), out
    expect(out).to match(/does-not-exist\.md/)
  end

  # The dangerous shape: one of each in the same file. An exemption that
  # swallowed the whole run would pass the example above and fail this one.
  it "fails on the dead link even beside an exempt one" do
    status, out = run_in_sandbox(
      doc_body: "[todo](reference/auto/todo.md) and [dead](reference/nope.md)\n",
      gitignored: [ "docs/reference/auto/todo.md" ]
    )
    expect(status).to eq(1), out
    expect(out).to match(/nope\.md/)
  end

  it "is unaffected for a target that exists" do
    status, out = run_in_sandbox(
      doc_body: "See [real](reference/real.md).\n",
      gitignored: [],
      create: [ "docs/reference/real.md" ]
    )
    expect(status).to eq(0), out
  end
end
