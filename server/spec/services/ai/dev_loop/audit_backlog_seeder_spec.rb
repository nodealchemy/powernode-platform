# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevLoop::AuditBacklogSeeder do
  let(:account) { create(:account) }

  let(:fixture_content) do
    <<~MARKDOWN
      # System Extension Audit — Verified Findings Backlog (test)

      Preamble line that should be ignored.

      ## F1-03 — S2 [M] gap (CONFIRMED)
      **File:** `extensions/system/server/app/services/system/fleet/phase_service.rb:42`
      **Claim:** Fleet phase advancement has a race between reap and subtask completion.
      **Evidence:** Live repro with two concurrent ticks.
      **Repro:** cd server && bundle exec rails runner 'tick twice'
      **Fix:** Serialize phase advancement under a row lock.

      ## F5-02 — S3 [XS] test-gap (CONFIRMED)
      **File:** `extensions/system/server/app/services/system/ip_management_service.rb`
      **Claim:** IpManagementService.allocate_ip has zero spec coverage.
      **Evidence:** No spec file exists.
      **Repro:** ls spec/services/system/
      **Fix:** Add allocate_ip/release_ip specs covering the nil-registry path.

      ## F2-09 — S2 [S] bug (RESCOPED)
      **File:** `somewhere.rb`
      **Claim:** Rescoped finding that must not be seeded.
      **Evidence:** n/a
      **Repro:** n/a
      **Fix:** n/a

      ## F8-01 — S4 [XS] polish (CONFIRMED)
      **File:** `somewhere_else.rb`
      **Claim:** S4 finding outside the default severity filter.
      **Evidence:** n/a
      **Repro:** n/a
      **Fix:** n/a

      ## F3-01 — S1 [M] bug (CONFIRMED)
      **File:** `extensions/system/server/app/services/system/fleet/fleet_autonomy_service.rb:387`
      **Claim:** The require_approval lane of the fleet autonomy loop is a dead end.
      **Evidence:** 928 pending approvals, zero ever executed.
      **Repro:** rails runner 'puts Ai::ApprovalRequest.where(source_type: "system_fleet").count'
      **Fix:** Decide execute-vs-plan-and-queue, then close the act arc.
    MARKDOWN
  end

  let(:fixture_path) do
    path = Rails.root.join("tmp", "audit_seeder_fixture_#{SecureRandom.hex(4)}.md")
    File.write(path, fixture_content)
    path
  end

  after { FileUtils.rm_f(fixture_path) }

  subject(:seeder) { described_class.new(account: account, path: fixture_path) }

  it "seeds CONFIRMED S2/S3 findings plus human-decision keys, skipping RESCOPED and S4" do
    result = seeder.call

    expect(result.total_parsed).to eq(5)
    expect(result.created).to eq(3)
    expect(result.ralph_loop.ralph_tasks.pluck(:task_key))
      .to contain_exactly("F1-03", "F5-02", "F3-01")
  end

  it "creates the loop configured for the dev_loop executor bridge" do
    ralph_loop = seeder.call.ralph_loop

    expect(ralph_loop.name).to eq(described_class::LOOP_NAME)
    expect(ralph_loop.ai_tool).to eq("claude_code")
    expect(ralph_loop.scheduling_mode).to eq("manual")
    expect(ralph_loop.branch).to eq("dev-loop/dev-audit")
    expect(ralph_loop.configuration["loop_spec_path"]).to eq(".claude/loops/dev-audit/PROMPT.md")
    expect(ralph_loop.configuration["guardrails"]).to include(a_string_matching(/failing spec/))
  end

  it "maps severity and size into priority" do
    tasks = seeder.call.ralph_loop.ralph_tasks.index_by(&:task_key)

    expect(tasks["F1-03"].priority).to eq(21) # S2 (20) + M (1)
    expect(tasks["F5-02"].priority).to eq(13) # S3 (10) + XS (3)
    expect(tasks["F3-01"].priority).to eq(31) # S1 (30) + M (1)
  end

  it "seeds human-decision findings as execution_type human without an executor hint" do
    tasks = seeder.call.ralph_loop.ralph_tasks.index_by(&:task_key)

    expect(tasks["F3-01"].execution_type).to eq("human")
    expect(tasks["F3-01"].metadata).not_to have_key("executor_hint")
    expect(tasks["F3-01"].acceptance_criteria).to match(/Operator decision required/)

    expect(tasks["F1-03"].execution_type).to eq("agent")
    expect(tasks["F1-03"].metadata["executor_hint"]).to eq("claude_code")
  end

  it "carries finding context into the task" do
    task = seeder.call.ralph_loop.ralph_tasks.find_by(task_key: "F1-03")

    expect(task.description).to match(/race between reap/)
    expect(task.acceptance_criteria).to match(/failing spec.*FIRST.*Serialize phase advancement/m)
    expect(task.metadata["severity"]).to eq("S2")
    expect(task.metadata["kind"]).to eq("gap")
    expect(task.metadata["files"]).to match(/phase_service\.rb:42/)
    expect(task.metadata["repro"]).to match(/tick twice/)
  end

  it "is idempotent — re-running creates nothing and touches nothing" do
    seeder.call
    task = Ai::RalphTask.find_by(task_key: "F1-03")
    task.start! # simulate in-flight work

    result = described_class.new(account: account, path: fixture_path).call

    expect(result.created).to eq(0)
    expect(result.skipped).to eq(3)
    expect(task.reload.status).to eq("in_progress")
  end

  it "respects a custom severity filter" do
    result = described_class.new(account: account, path: fixture_path, severities: %w[S4]).call

    expect(result.ralph_loop.ralph_tasks.pluck(:task_key))
      .to contain_exactly("F8-01", "F3-01")
  end
end
