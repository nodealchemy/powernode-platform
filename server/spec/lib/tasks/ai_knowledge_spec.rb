# frozen_string_literal: true

require "rails_helper"
require "open3"

# server/lib/tasks/ai_knowledge.rake (IMP-3c9a6dc8f0a9) — thin wrappers over
# Ai::Memory::SharedKnowledgeService#archive_by_predicate! /
# #hard_delete_archived!, whose dry-run/ceiling/audit behaviour is covered
# exhaustively in shared_knowledge_service_spec.rb. These specs verify only
# the rake-specific seam: PREDICATE_JSON/EXECUTE/ACCOUNT_ID env vars, and the
# invocation-level (cross-account) safety in
# Ai::BulkPredicateMutation#resolve_accounts_for_rake!/
# #enforce_aggregate_ceiling! — not re-proving the service's own per-account
# safety design.
RSpec.describe "ai:archive_knowledge_by_predicate / ai:hard_delete_archived_knowledge" do
  let!(:account) { create(:account) }

  # IMP-3c9a6dc8f0a9 review round (BLOCKER 2) — PREDICATE_JSON was a
  # bracketed rake TASK ARG, documented in the same breath as the ENV vars
  # EXECUTE/ACCOUNT_ID; an operator setting it as an env var like its two
  # neighbours silently got the widest possible scope. It is ENV now, like
  # its neighbours — set via ENV["PREDICATE_JSON"], not a positional arg to
  # Task#invoke, so this helper takes no args at all: nothing about how this
  # spec invokes the task differs from how the rake CLI does anymore.
  def run_task(name)
    previous_application = Rake.application
    previous_execute = ENV["EXECUTE"]
    previous_account_id = ENV["ACCOUNT_ID"]
    previous_predicate_json = ENV["PREDICATE_JSON"]
    begin
      Rake.application = Rake::Application.new
      Rake.application.rake_require("tasks/ai_knowledge", [ Rails.root.join("lib").to_s ], [])
      Rake::Task.define_task(:environment)
      silence_stream { Rake::Task[name].invoke }
    ensure
      Rake.application = previous_application
      ENV["EXECUTE"] = previous_execute
      ENV["ACCOUNT_ID"] = previous_account_id
      ENV["PREDICATE_JSON"] = previous_predicate_json
    end
  end

  def silence_stream
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  describe "ai:archive_knowledge_by_predicate" do
    let!(:matching) { create(:ai_shared_knowledge, account: account, source_type: "import") }
    let!(:other) { create(:ai_shared_knowledge, account: account, source_type: "manual") }

    it "defaults to dry_run (EXECUTE unset) and archives nothing, sweeping every account with no ACCOUNT_ID" do
      ENV.delete("EXECUTE")
      ENV.delete("ACCOUNT_ID")
      ENV["PREDICATE_JSON"] = '{"source_type":"import"}'

      run_task("ai:archive_knowledge_by_predicate")

      expect(matching.reload.provenance["archived"]).not_to eq(true)
    end

    it "aborts EXECUTE=true with no ACCOUNT_ID, mutating nothing" do
      ENV["EXECUTE"] = "true"
      ENV.delete("ACCOUNT_ID")
      ENV["PREDICATE_JSON"] = '{"source_type":"import"}'

      expect { run_task("ai:archive_knowledge_by_predicate") }.to raise_error(SystemExit)
      expect(matching.reload.provenance["archived"]).not_to eq(true)
    end

    it "archives the matching rows for that account when EXECUTE=true and ACCOUNT_ID is given" do
      ENV["EXECUTE"] = "true"
      ENV["ACCOUNT_ID"] = account.id
      ENV["PREDICATE_JSON"] = '{"source_type":"import"}'

      run_task("ai:archive_knowledge_by_predicate")

      expect(matching.reload.provenance["archived"]).to be true
      expect(other.reload.provenance["archived"]).not_to eq(true)
    end

    it "matches every not-yet-archived row in that account when PREDICATE_JSON is unset" do
      ENV["EXECUTE"] = "true"
      ENV["ACCOUNT_ID"] = account.id
      ENV.delete("PREDICATE_JSON")

      run_task("ai:archive_knowledge_by_predicate")

      expect(matching.reload.provenance["archived"]).to be true
      expect(other.reload.provenance["archived"]).to be true
    end

    # IMP-3c9a6dc8f0a9 review round — the in-process narrowing proof for a
    # MULTI-KEY PREDICATE_JSON (previously only single-key examples existed
    # here; the two-key proof lived only in shared_knowledge_service_spec.rb,
    # which the "real CLI invocation" spec below was pointed at incorrectly
    # — this example is the correction, on the path an operator actually
    # invokes). Both keys must narrow independently for this to pass.
    it "ANDs a multi-key PREDICATE_JSON for that account, matching only rows satisfying every key" do
      wrong_content_type = create(:ai_shared_knowledge, account: account, source_type: "import", content_type: "text")
      matching.update!(content_type: "reference")
      ENV["EXECUTE"] = "true"
      ENV["ACCOUNT_ID"] = account.id
      ENV["PREDICATE_JSON"] = '{"source_type":"import","content_type":"reference"}'

      run_task("ai:archive_knowledge_by_predicate")

      expect(matching.reload.provenance["archived"]).to be true
      expect(wrong_content_type.reload.provenance["archived"]).not_to eq(true)
      expect(other.reload.provenance["archived"]).not_to eq(true)
    end

    # IMP-3c9a6dc8f0a9 review round — THE DEFECT: a bare Account.find_each
    # loop checked Ai::BulkPredicateMutation's ceiling once PER ACCOUNT, so
    # N accounts each safely under the ceiling could sum to far more than it
    # across the whole invocation. Proven red-first against the pre-fix rake
    # task by hand (two 400-row accounts, EXECUTE=true, no account filter:
    # all 800 archived in one invocation) before this fix landed; scaled
    # down here (3+3 rows against a stubbed ceiling of 5) for a fast
    # permanent spec proving the identical property.
    #
    # IMP-3c9a6dc8f0a9 review round — REGRESSION FIX. This example used to
    # assert a SystemExit here, on a DRY RUN (EXECUTE unset). That was
    # itself a defect: a dry run sweeping every account (no ACCOUNT_ID) is
    # exactly how an operator surveys a backlog BEFORE touching anything,
    # and this task's own stated scale (~6,250 rows) exceeds the 500-row
    # ceiling by construction — the very first survey an operator ran would
    # abort instead of report. `enforce_aggregate_ceiling!` now only aborts
    # a MUTATING invocation; a dry run warns and completes. See the
    # separate example below for the still-aborts-on-a-real-run property.
    it "warns (not aborts) when the cross-account aggregate exceeds the ceiling on a dry run" do
      stub_const("Ai::BulkPredicateMutation::MAX_BULK_PER_CALL", 5)
      other_account = create(:account)
      create_list(:ai_shared_knowledge, 3, account: account, source_type: "import")
      create_list(:ai_shared_knowledge, 3, account: other_account, source_type: "import")
      ENV.delete("EXECUTE")
      ENV.delete("ACCOUNT_ID")
      ENV["PREDICATE_JSON"] = '{"source_type":"import"}'
      allow(Rails.logger).to receive(:warn)

      expect { run_task("ai:archive_knowledge_by_predicate") }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(a_string_including("per-invocation ceiling"))
      expect(Ai::SharedKnowledge.where(account: [ account, other_account ]).where(
        "provenance @> ?", { archived: true }.to_json
      )).not_to exist
    end

    it "still aborts a MUTATING run — mutating nothing — when the (ACCOUNT_ID-scoped) aggregate exceeds the ceiling" do
      stub_const("Ai::BulkPredicateMutation::MAX_BULK_PER_CALL", 2)
      create_list(:ai_shared_knowledge, 3, account: account, source_type: "import")
      ENV["EXECUTE"] = "true"
      ENV["ACCOUNT_ID"] = account.id
      ENV["PREDICATE_JSON"] = '{"source_type":"import"}'

      expect { run_task("ai:archive_knowledge_by_predicate") }.to raise_error(SystemExit)
      expect(Ai::SharedKnowledge.where(account: account).where(
        "provenance @> ?", { archived: true }.to_json
      )).not_to exist
    end
  end

  describe "ai:hard_delete_archived_knowledge" do
    let!(:archived) { create(:ai_shared_knowledge, account: account, provenance: { "archived" => true }) }
    let!(:not_archived) { create(:ai_shared_knowledge, account: account) }

    it "defaults to dry_run (EXECUTE unset) and destroys nothing, sweeping every account with no ACCOUNT_ID" do
      ENV.delete("EXECUTE")
      ENV.delete("ACCOUNT_ID")
      ENV.delete("PREDICATE_JSON")

      run_task("ai:hard_delete_archived_knowledge")

      expect(Ai::SharedKnowledge.where(id: archived.id)).to exist
    end

    it "aborts EXECUTE=true with no ACCOUNT_ID, destroying nothing" do
      ENV["EXECUTE"] = "true"
      ENV.delete("ACCOUNT_ID")
      ENV.delete("PREDICATE_JSON")

      expect { run_task("ai:hard_delete_archived_knowledge") }.to raise_error(SystemExit)
      expect(Ai::SharedKnowledge.where(id: archived.id)).to exist
    end

    it "hard-deletes only already-archived rows in that account when EXECUTE=true and ACCOUNT_ID is given" do
      ENV["EXECUTE"] = "true"
      ENV["ACCOUNT_ID"] = account.id
      ENV.delete("PREDICATE_JSON")

      run_task("ai:hard_delete_archived_knowledge")

      expect(Ai::SharedKnowledge.where(id: archived.id)).not_to exist
      expect(Ai::SharedKnowledge.where(id: not_archived.id)).to exist
    end
  end

  # IMP-3c9a6dc8f0a9 review round (BLOCKER 2) — the ABOVE specs invoke via
  # Rake::Task#invoke, which is process-internal. This spec goes through the
  # real, documented CLI entry point instead — `bundle exec rake`, a genuine
  # subprocess, ENV set the way an operator's shell would set it — with a
  # MULTI-KEY PREDICATE_JSON (i.e. one containing a comma), which is exactly
  # the shape that used to be DOA through a bracketed task arg (Rake splits
  # a bracketed arg string on commas before the task body ever runs).
  # ENV vars are never touched by Rake's own argument tokenizer at all —
  # bracketed-or-not, subprocess-or-not — so the one thing worth a real
  # subprocess is confirming that end to end, without the added operational
  # risk of a non-transactional (DatabaseCleaner truncation) example on a
  # test DB shared with other concurrently-running agents (see
  # spec/services/platform/status/account_lock_spec.rb's header comment:
  # truncation there once hung a run for ten minutes). A dry run needs no
  # DB state from this example at all — EXECUTE is left unset — so this
  # stays on ordinary transactional fixtures.
  #
  # WHAT THIS DOES AND DOES NOT PROVE (recorded per review, not changed —
  # the reviewer accepted this tradeoff explicitly). It proves the ENV var
  # survives the real Rake CLI's own argument handling intact — no
  # JSON::ParserError, no uncaught exception — which is the one thing only
  # a genuine subprocess through the real `bundle exec rake` entry point can
  # show. It deliberately does NOT assert that the predicate selected the
  # right rows (no `matching.reload.provenance["archived"]` assertion here)
  # — that would require the subprocess to see this example's own DB writes,
  # which transactional fixtures make invisible to a separate process by
  # construction, and the alternative (DatabaseCleaner truncation) carries
  # the operational risk noted above. The NARROWING assertion for a
  # MULTI-KEY predicate specifically — that it ANDs correctly and matches
  # only rows satisfying every key — is carried by "ANDs a multi-key
  # PREDICATE_JSON for that account..." above (in-process, `Rake::Task#invoke`,
  # ordinary transactional fixtures), which makes this subprocess spec fully
  # redundant on that property rather than merely weak on it — look there,
  # not here, and not at a single-key example, which cannot show it either.
  describe "the real CLI invocation (subprocess)" do
    it "reads a multi-key PREDICATE_JSON from ENV via the actual rake CLI, with no JSON-parse or arg-splitting corruption" do
      env = {
        "RAILS_ENV" => "test",
        "PREDICATE_JSON" => { source_type: "import", content_type: "reference" }.to_json
      }

      _stdout, stderr, _status = Open3.capture3(
        env, "bundle", "exec", "rake", "ai:archive_knowledge_by_predicate", chdir: Rails.root.to_s
      )

      # A clean dry-run report AND a graceful aggregate-ceiling abort (this
      # runs against every account on a test DB shared with other
      # concurrently-running agents, so either is a legitimate outcome) are
      # both fine here — what this narrowly proves is that the multi-key,
      # comma-containing PREDICATE_JSON survived ENV intact through the
      # real CLI. A JSON parse failure or an uncaught Ruby exception is
      # neither of those, and is what a still-bracketed arg would produce.
      expect(stderr).not_to include("JSON::ParserError"), "PREDICATE_JSON was corrupted in transit: #{stderr}"
      expect(stderr).not_to match(/\.rb:\d+:in [`']/), "an uncaught exception escaped the task: #{stderr}"
    end
  end
end
