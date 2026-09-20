# frozen_string_literal: true

require "rails_helper"
require "open3"

# server/lib/tasks/ai_learning.rake's :retire_learnings_by_predicate /
# :hard_delete_retired_learnings (IMP-3c9a6dc8f0a9) — thin wrappers over
# Ai::Learning::CompoundLearningService's predicate methods, whose dry-run/
# ceiling/audit behaviour is covered exhaustively in
# compound_learning_service_spec.rb. These specs verify only the
# rake-specific seam: PREDICATE_JSON/REASON/EXECUTE/ACCOUNT_ID env vars, and
# the invocation-level (cross-account) safety in
# Ai::BulkPredicateMutation#resolve_accounts_for_rake!/
# #enforce_aggregate_ceiling! (also unit-tested directly in
# bulk_predicate_mutation_spec.rb) — not re-proving the service's own
# per-account safety design.
RSpec.describe "ai:retire_learnings_by_predicate / ai:hard_delete_retired_learnings" do
  let!(:account) { create(:account) }

  # IMP-3c9a6dc8f0a9 review round (BLOCKER 2) — PREDICATE_JSON/REASON were
  # bracketed rake TASK ARGS, documented alongside the ENV vars EXECUTE/
  # ACCOUNT_ID; both are ENV now, like their neighbours — see
  # ai_knowledge_spec.rb's identical note. No positional args left to pass.
  def run_task(name)
    previous_application = Rake.application
    previous_execute = ENV["EXECUTE"]
    previous_account_id = ENV["ACCOUNT_ID"]
    previous_predicate_json = ENV["PREDICATE_JSON"]
    previous_reason = ENV["REASON"]
    begin
      Rake.application = Rake::Application.new
      Rake.application.rake_require("tasks/ai_learning", [ Rails.root.join("lib").to_s ], [])
      Rake::Task.define_task(:environment)
      silence_stream { Rake::Task[name].invoke }
    ensure
      Rake.application = previous_application
      ENV["EXECUTE"] = previous_execute
      ENV["ACCOUNT_ID"] = previous_account_id
      ENV["PREDICATE_JSON"] = previous_predicate_json
      ENV["REASON"] = previous_reason
    end
  end

  def silence_stream
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  describe "ai:retire_learnings_by_predicate" do
    let!(:matching) { create(:ai_compound_learning, account: account, status: "active", extraction_method: "trading_session") }
    let!(:other) { create(:ai_compound_learning, account: account, status: "active", extraction_method: "auto_success") }

    it "defaults to dry_run (EXECUTE unset) and retires nothing, sweeping every account with no ACCOUNT_ID" do
      ENV.delete("EXECUTE")
      ENV.delete("ACCOUNT_ID")
      ENV["PREDICATE_JSON"] = '{"extraction_method":"trading_session"}'
      ENV.delete("REASON")

      run_task("ai:retire_learnings_by_predicate")

      expect(matching.reload.status).to eq("active")
    end

    it "aborts EXECUTE=true with no ACCOUNT_ID, retiring nothing" do
      ENV["EXECUTE"] = "true"
      ENV.delete("ACCOUNT_ID")
      ENV["PREDICATE_JSON"] = '{"extraction_method":"trading_session"}'
      ENV["REASON"] = "purge"

      expect { run_task("ai:retire_learnings_by_predicate") }.to raise_error(SystemExit)
      expect(matching.reload.status).to eq("active")
    end

    it "retires the matching rows for that account and records the reason when EXECUTE=true and ACCOUNT_ID is given" do
      ENV["EXECUTE"] = "true"
      ENV["ACCOUNT_ID"] = account.id
      ENV["PREDICATE_JSON"] = '{"extraction_method":"trading_session"}'
      ENV["REASON"] = "purge"

      run_task("ai:retire_learnings_by_predicate")

      matching.reload
      expect(matching.status).to eq("retired")
      expect(matching.metadata["retired_reason"]).to eq("purge")
      expect(other.reload.status).to eq("active")
    end

    # IMP-3c9a6dc8f0a9 review round — the in-process narrowing proof for a
    # MULTI-KEY PREDICATE_JSON, on the path an operator actually invokes
    # (see ai_knowledge_spec.rb's identical example for the full rationale).
    it "ANDs a multi-key PREDICATE_JSON for that account, matching only rows satisfying every key" do
      wrong_category = create(:ai_compound_learning, account: account, status: "active",
                              extraction_method: "trading_session", category: "anti_pattern")
      matching.update!(category: "pattern")
      ENV["EXECUTE"] = "true"
      ENV["ACCOUNT_ID"] = account.id
      ENV["PREDICATE_JSON"] = '{"extraction_method":"trading_session","category":"pattern"}'
      ENV.delete("REASON")

      run_task("ai:retire_learnings_by_predicate")

      expect(matching.reload.status).to eq("retired")
      expect(wrong_category.reload.status).to eq("active")
      expect(other.reload.status).to eq("active")
    end

    # IMP-3c9a6dc8f0a9 review round (item 3) — same defect/fix as
    # ai_knowledge_spec.rb: a bare Account.find_each loop checked the
    # ceiling once PER ACCOUNT, so N accounts each under it could sum to
    # far more across the whole invocation. Scaled down here (3+3 rows
    # against a stubbed ceiling of 5).
    # IMP-3c9a6dc8f0a9 review round — REGRESSION FIX: see the identical
    # example in ai_knowledge_spec.rb for the full trace. A dry run
    # exceeding the ceiling now warns and completes rather than aborting —
    # surveying every account is the whole point of a dry run.
    it "warns (not aborts) when the cross-account aggregate exceeds the ceiling on a dry run" do
      stub_const("Ai::BulkPredicateMutation::MAX_BULK_PER_CALL", 5)
      other_account = create(:account)
      create_list(:ai_compound_learning, 3, account: account, status: "active", extraction_method: "trading_session")
      create_list(:ai_compound_learning, 3, account: other_account, status: "active", extraction_method: "trading_session")
      ENV.delete("EXECUTE")
      ENV.delete("ACCOUNT_ID")
      ENV["PREDICATE_JSON"] = '{"extraction_method":"trading_session"}'
      ENV.delete("REASON")
      allow(Rails.logger).to receive(:warn)

      expect { run_task("ai:retire_learnings_by_predicate") }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(a_string_including("per-invocation ceiling"))
      expect(Ai::CompoundLearning.where(account: [ account, other_account ], status: "retired")).not_to exist
    end

    it "still aborts a MUTATING run — retiring nothing — when the (ACCOUNT_ID-scoped) aggregate exceeds the ceiling" do
      stub_const("Ai::BulkPredicateMutation::MAX_BULK_PER_CALL", 2)
      create_list(:ai_compound_learning, 3, account: account, status: "active", extraction_method: "trading_session")
      ENV["EXECUTE"] = "true"
      ENV["ACCOUNT_ID"] = account.id
      ENV["PREDICATE_JSON"] = '{"extraction_method":"trading_session"}'
      ENV.delete("REASON")

      expect { run_task("ai:retire_learnings_by_predicate") }.to raise_error(SystemExit)
      expect(Ai::CompoundLearning.where(account: account, status: "retired")).not_to exist
    end
  end

  describe "ai:hard_delete_retired_learnings" do
    let!(:retired) { create(:ai_compound_learning, :retired, account: account, extraction_method: "trading_session") }
    let!(:active) { create(:ai_compound_learning, account: account, status: "active", extraction_method: "trading_session") }

    it "defaults to dry_run (EXECUTE unset) and destroys nothing, sweeping every account with no ACCOUNT_ID" do
      ENV.delete("EXECUTE")
      ENV.delete("ACCOUNT_ID")
      ENV["PREDICATE_JSON"] = '{"extraction_method":"trading_session"}'

      run_task("ai:hard_delete_retired_learnings")

      expect(Ai::CompoundLearning.where(id: retired.id)).to exist
    end

    it "aborts EXECUTE=true with no ACCOUNT_ID, destroying nothing" do
      ENV["EXECUTE"] = "true"
      ENV.delete("ACCOUNT_ID")
      ENV["PREDICATE_JSON"] = '{"extraction_method":"trading_session"}'

      expect { run_task("ai:hard_delete_retired_learnings") }.to raise_error(SystemExit)
      expect(Ai::CompoundLearning.where(id: retired.id)).to exist
    end

    it "hard-deletes only already-retired rows in that account when EXECUTE=true and ACCOUNT_ID is given" do
      ENV["EXECUTE"] = "true"
      ENV["ACCOUNT_ID"] = account.id
      ENV["PREDICATE_JSON"] = '{"extraction_method":"trading_session"}'

      run_task("ai:hard_delete_retired_learnings")

      expect(Ai::CompoundLearning.where(id: retired.id)).not_to exist
      expect(Ai::CompoundLearning.where(id: active.id)).to exist
    end
  end

  # IMP-3c9a6dc8f0a9 review round (BLOCKER 2) — the real CLI entry point,
  # subprocess, multi-key PREDICATE_JSON (a comma inside the JSON) — see
  # ai_knowledge_spec.rb's identical spec for the full rationale, including
  # why this deliberately does NOT use `truncation: true` / depend on the
  # subprocess seeing this example's own DB rows (non-transactional
  # DatabaseCleaner truncation on a test DB shared with other concurrently-
  # running agents is a documented operational risk — see
  # spec/services/platform/status/account_lock_spec.rb).
  #
  # WHAT THIS DOES AND DOES NOT PROVE (recorded per review, not changed).
  # It proves the ENV var survives the real Rake CLI's own argument
  # handling intact — no JSON::ParserError, no uncaught exception. It does
  # NOT assert the predicate selected the right rows — that needs the
  # subprocess to see this example's own DB writes, which transactional
  # fixtures make invisible to it by construction. The narrowing assertion
  # for a MULTI-KEY predicate specifically is carried by "ANDs a multi-key
  # PREDICATE_JSON for that account..." above (in-process), which makes
  # this subprocess spec fully redundant on that property — look there,
  # not here.
  describe "the real CLI invocation (subprocess)" do
    it "reads a multi-key PREDICATE_JSON from ENV via the actual rake CLI, with no JSON-parse or arg-splitting corruption" do
      env = {
        "RAILS_ENV" => "test",
        "PREDICATE_JSON" => { extraction_method: "trading_session", category: "pattern" }.to_json
      }

      _stdout, stderr, _status = Open3.capture3(
        env, "bundle", "exec", "rake", "ai:retire_learnings_by_predicate", chdir: Rails.root.to_s
      )

      expect(stderr).not_to include("JSON::ParserError"), "PREDICATE_JSON was corrupted in transit: #{stderr}"
      expect(stderr).not_to match(/\.rb:\d+:in [`']/), "an uncaught exception escaped the task: #{stderr}"
    end
  end
end
