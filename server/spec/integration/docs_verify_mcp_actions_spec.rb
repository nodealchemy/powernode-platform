# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "fileutils"

# IMP-01a05ec2 — a check that is red on every run reports nothing.
#
# docs/.verify/check-mcp-actions.sh greps the docs for `platform.<action>(`
# call sites and compares them against the tool registry. Two of the unknowns
# it finds — cost_analysis and recent_events — are REAL actions the running
# server exposes that the static grep of platform_api_tool_registry.rb cannot
# see, and both are catalogued as expected in docs/.verify/ASPIRATIONAL_MCP.md.
# The script's own closing line tells reviewers to "Cross-check unknowns
# against docs/.verify/ASPIRATIONAL_MCP.md" — it points at the allowlist and
# never reads it, so it exited 1 on EVERY run.
#
# The CI step is advisory (continue-on-error), so that never failed the
# workflow; it did something quieter and worse. A permanently-red advisory step
# is one nobody reads, and a genuinely new unknown moved the count from 2 to 3
# inside a step that was already failing — invisible.
#
# So the oracle is a GREEN BASELINE plus a red on something new. Asserting only
# "exit 0 today" would pass against a script that never fails at all, which is
# the same defect with the sign flipped — every example below therefore pins
# both arms.
RSpec.describe "docs/.verify/check-mcp-actions.sh", type: :integration do
  let(:repo_root) { Rails.root.join("..").cleanpath }
  let(:script) { repo_root.join("docs/.verify/check-mcp-actions.sh") }

  # THE ASSERTION THAT MATTERS OPERATIONALLY: the real tree, the real registry,
  # the real allowlist. Everything else here is a sandbox.
  it "is GREEN on this repository — the baseline a new unknown can disturb" do
    out = `bash #{Shellwords.escape(script.to_s)} 2>&1`
    expect($?.exitstatus).to eq(0), "check-mcp-actions.sh is red on a clean tree:\n#{out}"
  end

  it "still reports the expected unknowns rather than hiding them" do
    out = `bash #{Shellwords.escape(script.to_s)} 2>&1`
    expect(out).to match(/cost_analysis/)
    expect(out).to match(/recent_events/)
  end

  # --- sandbox: a whole fake platform root, so unknowns can be injected ---

  # Builds a minimal tree the script recognises: docs/, docs/.verify/ (a copy
  # of the REAL script under test, plus an allowlist) and the registry path it
  # greps. Returns the exit status and combined output.
  def run_in_sandbox(doc_body:, allowlisted:, registry_actions: %w[list_agents spawn_task])
    Dir.mktmpdir("mcp-actions-check") do |root|
      verify = File.join(root, "docs", ".verify")
      registry_dir = File.join(root, "server", "app", "services", "ai", "tools")
      FileUtils.mkdir_p(verify)
      FileUtils.mkdir_p(registry_dir)

      FileUtils.cp(script.to_s, File.join(verify, "check-mcp-actions.sh"))
      File.write(File.join(root, "docs", "guide.md"), doc_body)
      File.write(
        File.join(registry_dir, "platform_api_tool_registry.rb"),
        registry_actions.map { |a| %(        "#{a}" => { action: "#{a}" },\n) }.join
      )

      rows = allowlisted.map { |a| "| `#{a}` | `docs/guide.md` | expected unknown |\n" }.join
      File.write(File.join(verify, "ASPIRATIONAL_MCP.md"), <<~MD)
        # Aspirational MCP Actions

        | Action | Doc | Note |
        |--------|-----|------|
        #{rows}
      MD

      out = `bash #{Shellwords.escape(File.join(verify, 'check-mcp-actions.sh'))} 2>&1`
      [ $?.exitstatus, out ]
    end
  end

  it "exits 0 when every unknown is allowlisted" do
    status, out = run_in_sandbox(
      doc_body: "Call `platform.cost_analysis(x)` here.\n",
      allowlisted: %w[cost_analysis]
    )
    expect(status).to eq(0), out
  end

  # THE POINT OF THE WHOLE CHANGE: a NEW unknown is visible again.
  it "exits 1 on an unknown that is NOT allowlisted, even beside one that is" do
    status, out = run_in_sandbox(
      doc_body: "Call `platform.cost_analysis(x)` and `platform.brand_new_verb(y)`.\n",
      allowlisted: %w[cost_analysis]
    )
    expect(status).to eq(1), out
    expect(out).to match(/brand_new_verb/)
  end

  it "does not fail on an action the registry actually declares" do
    status, out = run_in_sandbox(
      doc_body: "Call `platform.list_agents(x)`.\n",
      allowlisted: []
    )
    expect(status).to eq(0), out
  end

  # AN ALLOWLIST THAT IS NEVER RE-EXAMINED ROTS. An entry whose action is no
  # longer referenced anywhere is a permanent exemption for a doc that no
  # longer exists — the same failure this check exists to prevent, one level up.
  it "names a STALE allowlist entry whose action nothing references any more" do
    status, out = run_in_sandbox(
      doc_body: "Call `platform.list_agents(x)`.\n",
      allowlisted: %w[long_gone_verb]
    )
    expect(out).to match(/long_gone_verb/), "a stale allowlist entry should be named:\n#{out}"
    expect(out).to match(/stale|no longer|unreferenced/i)
    # Reported, never fatal: a stale row is hygiene, not a broken doc.
    expect(status).to eq(0), out
  end
end
