# frozen_string_literal: true

require "rails_helper"

# IMP-3c9a6dc8f0a9 — the shared shape both bulk-mutation call sites
# (Ai::Memory::SharedKnowledgeService, Ai::Learning::CompoundLearningService)
# extend. Exercised here directly against a real model (Ai::SharedKnowledge,
# already loaded, no dedup/embedding machinery to stub around) so this spec
# is not itself the only oracle for the two real call sites — each service's
# own spec also proves the property against its real mutation block (see
# "counts and continues on a raising row" in both).
RSpec.describe Ai::BulkPredicateMutation do
  let(:account) { create(:account) }

  def call(scope:, dry_run: true, action: "ai.knowledge.bulk_archive", actor: nil, &block)
    described_class.call(
      account: account, scope: scope, dry_run: dry_run, actor: actor,
      action: action, predicate: { probe: true },
      serializer: ->(e) { { id: e.id } }, log_tag: "[Spec]", &block
    )
  end

  describe "the ceiling" do
    it "refuses rather than truncates when the predicate exceeds MAX_BULK_PER_CALL" do
      stub_const("#{described_class}::MAX_BULK_PER_CALL", 2)
      rows = create_list(:ai_shared_knowledge, 3, account: account)

      result = call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id)), dry_run: false) { |r| r.destroy!; true }

      expect(result[:success]).to be false
      expect(result[:count]).to eq(3)
      expect(result[:ceiling]).to eq(2)
      expect(Ai::SharedKnowledge.where(id: rows.map(&:id)).count).to eq(3)
    end
  end

  describe "dry_run (the default)" do
    it "returns the count and sample without mutating or auditing" do
      rows = create_list(:ai_shared_knowledge, 2, account: account)

      expect { call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id))) { |r| r.destroy!; true } }
        .not_to change(AuditLog, :count)
    end
  end

  # IMP-3c9a6dc8f0a9 review round — the defect: the audit write used to sit
  # after the mutation loop inside the SAME rescue that wrapped the loop, so
  # a raise partway through skipped it entirely. This is the fix's core
  # claim: one row's mutation raising is COUNTED, not fatal to the run or to
  # the audit record.
  describe "one row's mutation raising (the defect this fix closes)" do
    it "destroys the rows before and after the raising row, and counts it as failed rather than aborting" do
      rows = create_list(:ai_shared_knowledge, 3, account: account)
      raiser = rows[1]

      result = call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id)), dry_run: false) do |row|
        raise ActiveRecord::RecordNotDestroyed, "simulated FK constraint" if row.id == raiser.id

        row.destroy!
        true
      end

      expect(Ai::SharedKnowledge.where(id: rows[0].id)).not_to exist
      expect(Ai::SharedKnowledge.where(id: rows[2].id)).not_to exist
      expect(Ai::SharedKnowledge.where(id: raiser.id)).to exist

      expect(result[:success]).to be true
      expect(result[:count]).to eq(2)
      expect(result[:failed]).to eq(1)
      expect(result[:row_errors]).to contain_exactly(
        { id: raiser.id, error: a_string_including("simulated FK constraint") }
      )
    end

    it "writes an AuditLog entry recording exactly what happened, including the row-level error" do
      rows = create_list(:ai_shared_knowledge, 2, account: account)
      raiser = rows[0]

      call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id)), dry_run: false) do |row|
        raise "boom" if row.id == raiser.id

        row.destroy!
        true
      end

      log = AuditLog.last
      expect(log.metadata["requested_count"]).to eq(2)
      expect(log.metadata["affected_count"]).to eq(1)
      expect(log.metadata["failed"]).to eq(1)
      expect(log.metadata["row_errors"]).to contain_exactly("id" => raiser.id, "error" => a_string_including("boom"))
      expect(log.metadata["aborted"]).to eq(false)
    end
  end

  # THE ENSURE GUARANTEE, independent of the per-row rescue above. A per-row
  # `rescue StandardError` cannot catch a non-StandardError exit (Interrupt,
  # SystemExit — an operator's Ctrl-C mid-run is the realistic case) —
  # `ensure` still runs for those. This is why the audit write is an
  # `ensure`, not just "after a rescued loop": it is the ONE thing that
  # cannot be skipped by an exit the per-row rescue does not cover, and this
  # spec is the honest claim about what state it proves — do not read the
  # earlier examples as proving THIS property, since per-row rescue means a
  # plain StandardError never reaches the outer rescue at all.
  describe "the ensure guarantee on a non-StandardError exit" do
    it "still writes the audit record for the rows already mutated, then re-raises" do
      rows = create_list(:ai_shared_knowledge, 3, account: account)
      interrupted_at = rows[1]

      expect {
        call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id)), dry_run: false) do |row|
          raise Interrupt if row.id == interrupted_at.id

          row.destroy!
          true
        end
      }.to raise_error(Interrupt)

      expect(Ai::SharedKnowledge.where(id: rows[0].id)).not_to exist
      expect(Ai::SharedKnowledge.where(id: interrupted_at.id)).to exist
      expect(Ai::SharedKnowledge.where(id: rows[2].id)).to exist

      log = AuditLog.last
      expect(log.metadata["affected_count"]).to eq(1)
      expect(log.metadata["aborted"]).to eq(true)
      expect(log.metadata["abort_error"]).to include("Interrupt")
    end
  end

  # IMP-3c9a6dc8f0a9 review round — THE MESSAGE-CAN-LIE DEFECT. `#call`'s
  # rescue used to wrap the whole method, including `#mutate_and_audit` — so
  # an audit-write failure (raised inside `#mutate_and_audit`'s own
  # `ensure`, AFTER rows were already mutated) unwound into that rescue and
  # was reported as "failed before any mutation": false, since mutation had
  # already happened. Two things are proven separately here: the rescue is
  # now scoped narrowly enough that it cannot make that claim falsely, and
  # an audit-write failure is reported as a (successful) mutation with
  # `audit_failed: true`, never as `success: false`.
  describe "an audit-write failure (the message-can-lie defect this fix closes)" do
    it "reports the mutation as successful with audit_failed: true, not success: false" do
      rows = create_list(:ai_shared_knowledge, 2, account: account)
      allow(AuditLog).to receive(:log_action).and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))

      result = call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id)), dry_run: false) { |r| r.destroy!; true }

      expect(Ai::SharedKnowledge.where(id: rows.map(&:id))).not_to exist
      expect(result[:success]).to be true
      expect(result[:count]).to eq(2)
      expect(result[:audit_failed]).to be true
    end

    it "does not surface audit_failed when the audit write succeeds" do
      rows = create_list(:ai_shared_knowledge, 1, account: account)

      result = call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id)), dry_run: false) { |r| r.destroy!; true }

      expect(result).not_to have_key(:audit_failed)
    end
  end

  # IMP-3c9a6dc8f0a9 review round (BLOCKER 1) — the actual production defect,
  # not just the mechanism. Audit::LoggingService#should_rate_limit? caps
  # actions matching /admin|delete/ (both our hard-delete action names do)
  # at 5 per hour, and hard-codes `return false if Rails.env.test?` — so no
  # spec routed through that sink could ever observe the rate limit firing.
  #
  # WHICH ASSERTION ACTUALLY PROVES THE FIX (corrected per review — the
  # first draft of this comment credited the wrong one): it is
  # `expect(Audit::LoggingService.instance).not_to receive(:log)` — THAT is
  # what goes red on a revert to the old sink, because it directly detects
  # whether `#log` was ever called, independent of test-env rate limiting.
  # The "6 AuditLog rows" count below is a real, additional confirmation
  # that nothing else silently ate a write, but it CANNOT by itself
  # distinguish old code from new: since should_rate_limit? always returns
  # false in test, even the old, wrong `Audit::LoggingService.instance.log`
  # call would also have produced 6 rows in this environment — the count
  # assertion alone would pass on either sink. It is the mock expectation
  # that carries this test's actual claim.
  describe "is not subject to Audit::LoggingService's rate limiting or error swallowing" do
    it "writes an AuditLog row for every one of 6 real hard-delete-shaped calls in one run (exceeding the production 5/hour /delete/ ceiling)" do
      expect(Audit::LoggingService.instance).not_to receive(:log)
      rows = create_list(:ai_shared_knowledge, 6, account: account)

      6.times do |i|
        call(scope: Ai::SharedKnowledge.where(id: rows[i].id), dry_run: false,
             action: "ai.knowledge.bulk_hard_delete") { |r| r.destroy!; true }
      end

      expect(AuditLog.where(action: "ai.knowledge.bulk_hard_delete").count).to eq(6)
    end
  end

  # IMP-3c9a6dc8f0a9 review round — bypassing Audit::LoggingService#log
  # dropped more than the two defeats above (rate limit, swallowed
  # rescue), which is all the original direction argued. Fixed narrowly:
  # explicit source: (never the "web" #log_action defaults to), threading
  # through whatever request context IS available (empty for a rake run),
  # and NOT dropping the real-time monitoring hook.
  describe "source attribution (never defaults to \"web\")" do
    it "records source: automation for a nil actor (rake-driven)" do
      rows = create_list(:ai_shared_knowledge, 1, account: account)

      call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id)), dry_run: false, actor: nil) { |r| r.destroy!; true }

      expect(AuditLog.last.source).to eq("automation")
    end

    it "records source: api for a present actor (MCP-tool-driven)" do
      user = create(:user)
      rows = create_list(:ai_shared_knowledge, 1, account: account)

      call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id)), dry_run: false, actor: user) { |r| r.destroy!; true }

      expect(AuditLog.last.source).to eq("api")
    end
  end

  describe "request context (threaded through, not silently dropped)" do
    it "carries ip_address/user_agent onto the AuditLog row when Audit::LoggingService has a current_context" do
      rows = create_list(:ai_shared_knowledge, 1, account: account)
      Audit::LoggingService.instance.with_context(ip_address: "203.0.113.5", user_agent: "test-agent/1.0") do
        call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id)), dry_run: false) { |r| r.destroy!; true }
      end

      log = AuditLog.last
      expect(log.ip_address).to eq("203.0.113.5")
      expect(log.user_agent).to eq("test-agent/1.0")
    end

    it "leaves ip_address/user_agent nil when there is no context (a plain rake run)" do
      rows = create_list(:ai_shared_knowledge, 1, account: account)

      call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id)), dry_run: false) { |r| r.destroy!; true }

      log = AuditLog.last
      expect(log.ip_address).to be_nil
      expect(log.user_agent).to be_nil
    end
  end

  describe "the real-time monitoring hook (not silently dropped)" do
    it "calls monitor_event after a successful write when should_monitor? is true" do
      logging_service = Audit::LoggingService.instance
      allow(logging_service).to receive(:should_monitor?).and_return(true)
      expect(logging_service).to receive(:monitor_event)
      rows = create_list(:ai_shared_knowledge, 1, account: account)

      call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id)), dry_run: false) { |r| r.destroy!; true }
    end

    it "does not call monitor_event when should_monitor? is false" do
      logging_service = Audit::LoggingService.instance
      allow(logging_service).to receive(:should_monitor?).and_return(false)
      expect(logging_service).not_to receive(:monitor_event)
      rows = create_list(:ai_shared_knowledge, 1, account: account)

      call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id)), dry_run: false) { |r| r.destroy!; true }
    end

    it "does not mark the audit as failed when monitor_event itself raises — the AuditLog row is already committed" do
      logging_service = Audit::LoggingService.instance
      allow(logging_service).to receive(:should_monitor?).and_return(true)
      allow(logging_service).to receive(:monitor_event).and_raise("broadcast down")
      rows = create_list(:ai_shared_knowledge, 1, account: account)

      result = call(scope: Ai::SharedKnowledge.where(id: rows.map(&:id)), dry_run: false) { |r| r.destroy!; true }

      expect(result[:success]).to be true
      expect(result[:audit_failed]).not_to be true
      expect(AuditLog.last).not_to be_nil
    end
  end

  describe "the pre-mutation rescue's honesty" do
    it "only fires — and its message only holds — for a failure genuinely before any mutation" do
      rows = create_list(:ai_shared_knowledge, 1, account: account)
      allow(Ai::SharedKnowledge).to receive(:where).and_call_original
      broken_scope = Ai::SharedKnowledge.where(id: rows.map(&:id))
      allow(broken_scope).to receive(:count).and_raise("boom before mutation")

      result = call(scope: broken_scope, dry_run: false) { |r| r.destroy!; true }

      expect(result[:success]).to be false
      expect(result[:error]).to eq("boom before mutation")
      expect(Ai::SharedKnowledge.where(id: rows.map(&:id))).to exist # genuinely untouched
    end
  end

  # IMP-3c9a6dc8f0a9 review round (item 3) — a bare `Account.find_each` loop
  # in the rake tasks checked the ceiling once PER ACCOUNT, so N accounts
  # each safely under it could sum to far more across the whole invocation.
  # Unit-tested here against fake preview counts (fast, no need to create
  # hundreds of real rows); the rake-task spec additionally proves the same
  # property end-to-end with real records.
  describe ".enforce_aggregate_ceiling!" do
    it "aborts a MUTATING invocation when no single account exceeds the ceiling but their sum does" do
      stub_const("#{described_class}::MAX_BULK_PER_CALL", 500)
      account_a = create(:account)
      account_b = create(:account)
      previews = [ [ account_a, { count: 400 } ], [ account_b, { count: 400 } ] ]

      expect { described_class.enforce_aggregate_ceiling!(previews, dry_run: false) }.to raise_error(SystemExit)
    end

    it "returns the aggregate and does not abort when the sum is at or under the ceiling" do
      stub_const("#{described_class}::MAX_BULK_PER_CALL", 500)
      previews = [ [ create(:account), { count: 300 } ], [ create(:account), { count: 200 } ] ]

      expect(described_class.enforce_aggregate_ceiling!(previews, dry_run: false)).to eq(500)
    end

    # IMP-3c9a6dc8f0a9 review round — REGRESSION FIX: this used to abort
    # unconditionally, including on a dry run — but a dry run sweeping
    # every account (no ACCOUNT_ID) is exactly how an operator surveys a
    # backlog before touching anything, and this task's own stated scale
    # (~6,250 rows) exceeds the 500-row ceiling by construction. The very
    # first survey an operator ran would abort instead of report.
    it "warns and returns the aggregate on a DRY RUN, even over the ceiling — a dry run mutates nothing to protect against" do
      stub_const("#{described_class}::MAX_BULK_PER_CALL", 500)
      previews = [ [ create(:account), { count: 400 } ], [ create(:account), { count: 400 } ] ]
      allow(Rails.logger).to receive(:warn)

      result = nil
      expect { result = described_class.enforce_aggregate_ceiling!(previews, dry_run: true) }.not_to raise_error

      expect(result).to eq(800)
      expect(Rails.logger).to have_received(:warn).with(a_string_including("per-invocation ceiling"))
    end
  end

  describe ".resolve_accounts_for_rake!" do
    it "aborts when EXECUTE (dry_run: false) is requested without an ACCOUNT_ID" do
      expect { described_class.resolve_accounts_for_rake!(account_id: nil, dry_run: false) }
        .to raise_error(SystemExit)
    end

    it "aborts when the given ACCOUNT_ID matches no account" do
      expect { described_class.resolve_accounts_for_rake!(account_id: SecureRandom.uuid, dry_run: false) }
        .to raise_error(SystemExit)
    end

    it "scopes to exactly the named account on a mutating run" do
      other_account = create(:account)

      result = described_class.resolve_accounts_for_rake!(account_id: account.id, dry_run: false)

      expect(result.to_a).to eq([ account ])
      expect(result).not_to include(other_account)
    end

    it "returns every account for a dry run with no ACCOUNT_ID" do
      other_account = create(:account)

      result = described_class.resolve_accounts_for_rake!(account_id: nil, dry_run: true)

      expect(result).to include(account, other_account)
    end
  end
end
