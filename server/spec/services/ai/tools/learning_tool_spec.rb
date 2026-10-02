# frozen_string_literal: true

require "rails_helper"

# IMP-3470890a626f — query_learnings chained one .where per keyword (strict
# AND), so any multi-word intent query where the words don't all land in one
# row returned zero results while each single word returned many. The fix
# routes query-bearing calls through CompoundLearningService's existing
# embedding-first retrieval (OR keyword fallback when no embedding), WITHOUT
# record_injection! — an MCP query has no completing execution to credit, so
# counting it as an injection would depress effectiveness exactly the way the
# uncredited dev-loop injections did (IMP-5f8a744b8892).
RSpec.describe Ai::Tools::LearningTool do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:tool)    { described_class.new(account: account, user: user) }

  # Force the keyword-fallback retrieval path deterministically (no embedding
  # infrastructure in specs) — mirrors dev_loop_tool_spec's convention.
  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
  end

  let!(:learning) do
    create(:ai_compound_learning, account: account, status: "active",
           title: "Idempotent reconciliation",
           content: "Widget reconciliation must be idempotent across retries",
           importance_score: 0.8)
  end

  # create_learning said "similar learning reinforced" on ANY non-create
  # outcome (including a validation failure) and never returned an id.
  describe "create_learning" do
    before { allow(WorkerJobService).to receive(:enqueue_ai_dedup_learning) }

    it "returns the new learning's id" do
      result = tool.send(:call, action: "create_learning", category: "discovery",
                                content: "Queue consumers must ack only after the write commits")

      expect(result[:success]).to be true
      expect(result[:outcome]).to eq("created")
      created = Ai::CompoundLearning.find(result[:learning_id])
      expect(created.content).to eq("Queue consumers must ack only after the write commits")
    end

    it "returns the reinforced learning's id for a near-duplicate" do
      result = tool.send(:call, action: "create_learning", category: "discovery", content: learning.content)

      expect(result[:success]).to be true
      expect(result[:outcome]).to eq("reinforced")
      expect(result[:learning_id]).to eq(learning.id)
    end

    it "reports a validation failure instead of claiming a reinforcement" do
      invalid = Ai::CompoundLearning.new
      invalid.errors.add(:content, "is invalid")
      allow(Ai::CompoundLearning).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(invalid))

      result = tool.send(:call, action: "create_learning", category: "discovery",
                                content: "A brand new lesson nobody has recorded yet")

      expect(result[:success]).to be false
      expect(result[:error]).to include("Content is invalid")
      expect(result[:error]).not_to match(/reinforced/i)
    end
  end

  describe "query_learnings with a multi-word intent query" do
    it "returns learnings matching ANY of the query words (not strict AND)" do
      # "budget" and "cadence" appear in no learning; under the old chained
      # .where every keyword had to hit the SAME row, so this returned zero.
      result = tool.send(:call, action: "query_learnings",
                               query: "widget reconciliation budget cadence")

      expect(result[:success]).to be true
      expect(result[:learnings].map { |l| l[:id] }).to include(learning.id)
    end

    it "does not record an injection for a recall query" do
      tool.send(:call, action: "query_learnings", query: "widget reconciliation")

      expect(learning.reload.injection_count).to eq(0)
    end

    it "is safe against quote characters in the query" do
      result = tool.send(:call, action: "query_learnings",
                               query: "o'brien's widget reconciliation")

      expect(result[:success]).to be true
      expect(result[:learnings].map { |l| l[:id] }).to include(learning.id)
    end

    it "still honors the category filter on the semantic path" do
      other = create(:ai_compound_learning, account: account, status: "active",
                     category: "failure_mode",
                     content: "Widget reconciliation failure pattern")

      result = tool.send(:call, action: "query_learnings",
                               query: "widget reconciliation", category: "failure_mode")

      ids = result[:learnings].map { |l| l[:id] }
      expect(ids).to include(other.id)
      expect(ids).not_to include(learning.id)
    end
  end

  # IMP-8673c0533e24 (review round #5): reinforce_learning had no spec at all
  # before this — added when record_injection_outcome!(successful: true) was
  # (wrongly, then restored) touched by that task, to pin the counters it
  # actually produces.
  describe "reinforce_learning" do
    include PermissionTestHelpers

    let(:user) { user_with_permissions("ai.memory.write", account: account) }
    let(:loop_record) { create(:ai_ralph_loop, account: account) }
    let!(:task) do
      create(:ai_ralph_task, :in_progress, ralph_loop: loop_record,
             metadata: { "claimed_by" => "user:#{user.id}", "injected_learning_ids" => [ learning.id ] })
    end

    def reinforce(id = learning.id, t = tool)
      t.send(:call, action: "reinforce_learning", learning_id: id)
    end

    it "credits a learning injected into the caller's own claim" do
      result = reinforce

      expect(result[:success]).to be true
      learning.reload
      expect(learning.positive_outcome_count).to eq(1)
      expect(learning.negative_outcome_count).to eq(0)
    end

    it "does not recount the injection (it was counted when it was handed over)" do
      expect { reinforce }.not_to(change { learning.reload.injection_count })
    end

    it "boosts importance and returns it" do
      result = reinforce

      expect(result[:new_importance]).to be > 0.8
      expect(learning.reload.importance_score.to_f).to eq(result[:new_importance])
    end

    it "resolves the injection so a later citation cannot credit it twice" do
      reinforce
      reinforce_again = reinforce

      expect(reinforce_again[:success]).to be false
      expect(learning.reload.positive_outcome_count).to eq(1)
      expect(Array(task.reload.metadata["injected_learning_ids"])).not_to include(learning.id)
    end

    it "refuses a learning that was never injected into the caller's context, writing nothing" do
      other = create(:ai_compound_learning, account: account, status: "active", importance_score: 0.5)

      expect { @result = reinforce(other.id) }.not_to(change { other.reload.attributes })
      expect(@result[:success]).to be false
      expect(@result[:error]).to match(/injected/i)
    end

    it "refuses when the injection belongs to another principal's claim" do
      task.merge_metadata!("claimed_by" => "user:#{SecureRandom.uuid}")

      expect { @result = reinforce }.not_to(change { learning.reload.attributes })
      expect(@result[:success]).to be false
    end

    it "refuses when the claim is no longer in progress" do
      task.update!(status: "passed", iteration_completed_at: Time.current, completed_in_iteration: 1)

      expect { @result = reinforce }.not_to(change { learning.reload.attributes })
      expect(@result[:success]).to be false
    end

    it "refuses a claim from another account" do
      foreign = create(:ai_ralph_loop, account: create(:account))
      task.update!(ralph_loop: foreign)

      expect { @result = reinforce }.not_to(change { learning.reload.attributes })
      expect(@result[:success]).to be false
    end

    it "refuses a caller with no principal to match a claim against" do
      anonymous = described_class.new(account: account, internal: true)

      expect { @result = reinforce(learning.id, anonymous) }.not_to(change { learning.reload.attributes })
      expect(@result[:success]).to be false
    end

    it "does not let a principal-less caller match a claim stamped with a blank owner" do
      task.merge_metadata!("claimed_by" => "")
      anonymous = described_class.new(account: account, internal: true)

      expect { @result = reinforce(learning.id, anonymous) }.not_to(change { learning.reload.attributes })
      expect(@result[:success]).to be false
    end

    it "refuses a retired learning even when it was injected" do
      learning.update!(status: "retired")

      expect { @result = reinforce }.not_to(change { learning.reload.attributes })
      expect(@result[:success]).to be false
      expect(task.reload.metadata["injected_learning_ids"]).to eq([ learning.id ])
    end

    it "returns an error for an unknown learning id" do
      expect(reinforce(SecureRandom.uuid)[:success]).to be false
    end
  end

  describe "query_learnings without a query" do
    it "keeps the filtered browse behavior" do
      result = tool.send(:call, action: "query_learnings")

      expect(result[:success]).to be true
      expect(result[:learnings].map { |l| l[:id] }).to include(learning.id)
    end
  end

  # IMP-3c9a6dc8f0a9
  describe "retire_by_predicate" do
    let!(:matching) { create(:ai_compound_learning, account: account, status: "active", extraction_method: "trading_session") }

    it "defaults to dry_run and mutates nothing when dry_run is omitted" do
      result = tool.send(:call, action: "retire_by_predicate", extraction_method: "trading_session")

      expect(result[:dry_run]).to be true
      expect(matching.reload.status).to eq("active")
    end

    it "retires only the matching rows when dry_run: false is explicit" do
      result = tool.send(:call, action: "retire_by_predicate", extraction_method: "trading_session", dry_run: false)

      expect(result[:success]).to be true
      expect(matching.reload.status).to eq("retired")
      expect(learning.reload.status).to eq("active")
    end
  end

  describe "hard_delete_retired" do
    let!(:retired) { create(:ai_compound_learning, :retired, account: account, extraction_method: "trading_session") }

    it "defaults to dry_run and destroys nothing when dry_run is omitted" do
      tool.send(:call, action: "hard_delete_retired", extraction_method: "trading_session")

      expect(Ai::CompoundLearning.where(id: retired.id)).to exist
    end

    it "hard-deletes only already-retired/superseded rows when dry_run: false is explicit" do
      result = tool.send(:call, action: "hard_delete_retired", extraction_method: "trading_session", dry_run: false)

      expect(result[:success]).to be true
      expect(Ai::CompoundLearning.where(id: retired.id)).not_to exist
      expect(Ai::CompoundLearning.where(id: learning.id)).to exist
    end
  end
end
