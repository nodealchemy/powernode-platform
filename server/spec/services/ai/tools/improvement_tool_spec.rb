# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::ImprovementTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }

  def create_offer(overrides = {})
    tool.execute(params: {
      action: "create_improvement",
      recommendation_type: "code_lint",
      title: "Unused variable in foo",
      fingerprint: "code_lint|server/app/foo.rb|UnusedVar",
      files: ["server/app/foo.rb"],
      fix: "Remove the unused variable",
      verifier_evidence: "rubocop flags Lint/UselessAssignment at foo.rb:12 on HEAD",
      confidence_score: 0.8
    }.merge(overrides))
  end

  describe ".definition / .action_definitions" do
    it "requires the ai.agents.update permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.agents.update")
    end

    it "exposes the full improvement action set" do
      expect(described_class.action_definitions.keys).to contain_exactly(
        "discover_improvements", "create_improvement", "list_improvements",
        "approve_improvement", "dismiss_improvement", "revert_improvement",
        "enable_autonomy", "disable_autonomy", "scoreboard"
      )
    end
  end

  describe "discover_improvements" do
    it "returns general discovery guidance when no class_tag is given" do
      result = tool.execute(params: { action: "discover_improvements" })

      expect(result[:success]).to be true
      expect(result[:data][:mode]).to eq("general")
      expect(result[:data][:guidance]).to include("pattern-validation")
    end

    describe "class-sweep mode (class_tag)" do
      it "returns sweep guidance plus the account's known instances from tagged learnings" do
        create(:ai_compound_learning, account: account,
               title: "Server enqueues worker-only job constants",
               tags: ["class:server-worker-jobseam"])
        create(:ai_compound_learning, account: account, tags: ["unrelated"])
        create(:ai_compound_learning, :deprecated, account: account, tags: ["class:server-worker-jobseam"])
        create(:ai_compound_learning, account: create(:account), tags: ["class:server-worker-jobseam"])

        result = tool.execute(params: { action: "discover_improvements", class_tag: "class:server-worker-jobseam" })

        expect(result[:success]).to be true
        expect(result[:data][:mode]).to eq("class_sweep")
        expect(result[:data][:class_tag]).to eq("class:server-worker-jobseam")
        expect(result[:data][:known_instances].size).to eq(1)
        expect(result[:data][:known_instances].first[:title]).to eq("Server enqueues worker-only job constants")
        # exhaustive semantics: the whole class in one pass, fingerprints carry the class tag
        expect(result[:data][:guidance]).to include("ONE pass")
        expect(result[:data][:guidance]).to include("class:server-worker-jobseam|<file>")
      end

      it "still returns sweep guidance when no learnings carry the tag yet" do
        result = tool.execute(params: { action: "discover_improvements", class_tag: "class:ghost" })

        expect(result[:success]).to be true
        expect(result[:data][:mode]).to eq("class_sweep")
        expect(result[:data][:known_instances]).to eq([])
      end
    end
  end

  describe "create_improvement" do
    it "persists a pending code-quality offer with the fingerprint in evidence" do
      result = create_offer

      expect(result[:success]).to be true
      expect(result[:data][:deduped]).to be false
      rec = Ai::ImprovementRecommendation.find(result[:data][:recommendation][:id])
      expect(rec.status).to eq("pending")
      expect(rec.recommendation_type).to eq("code_lint")
      expect(rec.evidence["fingerprint"]).to eq("code_lint|server/app/foo.rb|UnusedVar")
      expect(rec.confidence_score).to eq(0.8)
      expect(rec.target_type).to eq("Account")
    end

    it "is idempotent on fingerprint — re-offering updates the open offer" do
      create_offer
      second = create_offer(title: "Unused variable (refined)")

      expect(second[:data][:deduped]).to be true
      expect(Ai::ImprovementRecommendation.where(account: account).count).to eq(1)
      expect(Ai::ImprovementRecommendation.first.evidence["title"]).to eq("Unused variable (refined)")
    end

    it "rejects a non-code-quality recommendation_type" do
      result = create_offer(recommendation_type: "provider_switch")
      expect(result[:success]).to be false
      expect(result[:error]).to include("must be one of")
    end

    it "requires fingerprint and title" do
      expect(create_offer(fingerprint: "")[:success]).to be false
      expect(create_offer(title: "")[:success]).to be false
    end

    it "tags a private-extension finding to its extension (gate #9), never globalizing it" do
      result = tool.execute(params: {
        action: "create_improvement", recommendation_type: "dead_code",
        title: "Dead method", fingerprint: "dead|acme|x",
        files: ["extensions/private/acme/server/app/x.rb"]
      })
      expect(result[:success]).to be true
      expect(result[:data][:recommendation][:extension]).to eq("acme")
    end
  end

  describe "list_improvements" do
    it "returns pending offers newest-first" do
      create_offer
      result = tool.execute(params: { action: "list_improvements" })
      expect(result[:success]).to be true
      expect(result[:data][:improvements].size).to eq(1)
      expect(result[:data][:improvements].first[:type]).to eq("code_lint")
    end
  end

  describe "approve_improvement" do
    it "approves the offer and promotes it to a dev-improve Ralph task with a back-link" do
      rec_id = create_offer[:data][:recommendation][:id]

      result = tool.execute(params: { action: "approve_improvement", recommendation_id: rec_id })

      expect(result[:success]).to be true
      expect(result[:data][:loop]).to eq("dev-improve")
      loop_record = account.ai_ralph_loops.find_by(name: "dev-improve")
      expect(loop_record.branch).to eq("dev-loop/dev-improve")
      task = loop_record.ralph_tasks.find_by(task_key: result[:data][:task_key])
      expect(task.metadata["recommendation_id"]).to eq(rec_id)
      expect(task.execution_type).to eq("agent")
      expect(task.metadata["blast_radius"]).to eq(1) # Tier-2(c): files count -> metric weight
      expect(Ai::ImprovementRecommendation.find(rec_id).status).to eq("approved")
    end

    it "is idempotent — approving twice does not create a duplicate task" do
      rec_id = create_offer[:data][:recommendation][:id]
      first = tool.execute(params: { action: "approve_improvement", recommendation_id: rec_id })
      second = tool.execute(params: { action: "approve_improvement", recommendation_id: rec_id })

      expect(second[:data][:task_key]).to eq(first[:data][:task_key])
      loop_record = account.ai_ralph_loops.find_by(name: "dev-improve")
      expect(loop_record.ralph_tasks.count).to eq(1)
    end

    it "is a no-op when the account kill switch is active" do
      rec_id = create_offer[:data][:recommendation][:id]
      allow_any_instance_of(Account).to receive(:ai_suspended?).and_return(true)

      result = tool.execute(params: { action: "approve_improvement", recommendation_id: rec_id })

      expect(result[:data][:halted]).to be true
      expect(account.ai_ralph_loops.find_by(name: "dev-improve")).to be_nil
    end

    # IMP-c4d5b7abb697: this tool's approve_improvement unconditionally promoted
    # ANY recommendation into a dev-improve CODING task, including non-code
    # types like agent_reliability written by the weekly policy-tuning writer.
    # Promotion must stay confined to CODE_QUALITY_TYPES.
    it "refuses to promote a non-code-quality recommendation into a dev-improve task" do
      rec = create(:ai_improvement_recommendation,
                   account: account,
                   recommendation_type: "agent_reliability",
                   status: "pending",
                   target_type: "Account",
                   target_id: account.id,
                   evidence: { "title" => "Only 16.7% approval rate — agent may need retraining" })

      result = tool.execute(params: { action: "approve_improvement", recommendation_id: rec.id })

      expect(result[:success]).to be false
      expect(result[:error]).to include("agent_reliability")
      expect(result[:error]).to include("not a code-quality recommendation")
      expect(rec.reload.status).to eq("pending")
      expect(account.ai_ralph_loops.find_by(name: "dev-improve")).to be_nil
      expect(Ai::RalphTask.where("metadata->>'recommendation_id' = ?", rec.id)).to be_empty
    end
  end

  describe "dismiss_improvement" do
    it "dismisses an offer so it is never promoted" do
      rec_id = create_offer[:data][:recommendation][:id]
      result = tool.execute(params: { action: "dismiss_improvement", recommendation_id: rec_id })

      expect(result[:success]).to be true
      expect(Ai::ImprovementRecommendation.find(rec_id).status).to eq("dismissed")
    end
  end

  # ==========================================================================
  # Tier-2(b): first-class repository scoping via the polymorphic target
  # ==========================================================================
  describe "repository scoping (Tier-2b)" do
    let(:repo) { create(:git_repository, account: account) }

    it "targets the GitRepository first-class when the repository resolves by id" do
      result = create_offer(repository: repo.id)
      rec = Ai::ImprovementRecommendation.find(result[:data][:recommendation][:id])

      expect(rec.target_type).to eq("Devops::GitRepository")
      expect(rec.target_id).to eq(repo.id)
      expect(result[:data][:recommendation][:repository_id]).to eq(repo.id)
      # evidence label normalizes to the repo full_name for display
      expect(rec.evidence["repository"]).to eq(repo.full_name)
    end

    it "resolves a repository by full_name" do
      result = create_offer(repository: repo.full_name)
      rec = Ai::ImprovementRecommendation.find(result[:data][:recommendation][:id])
      expect(rec.target_type).to eq("Devops::GitRepository")
      expect(rec.target_id).to eq(repo.id)
    end

    it "falls back to an Account target when the repository does not resolve" do
      result = create_offer(repository: "ghost/unknown-repo")
      rec = Ai::ImprovementRecommendation.find(result[:data][:recommendation][:id])
      expect(rec.target_type).to eq("Account")
      expect(rec.evidence["repository"]).to eq("ghost/unknown-repo")
    end

    it "dedupes per-target: the same fingerprint in two repositories is two distinct offers" do
      other = create(:git_repository, account: account)
      create_offer(repository: repo.id)
      second = create_offer(repository: other.id)

      expect(second[:data][:deduped]).to be false
      expect(Ai::ImprovementRecommendation.by_repository(repo.id).count).to eq(1)
      expect(Ai::ImprovementRecommendation.by_repository(other.id).count).to eq(1)
    end

    it "still dedupes the same fingerprint within one repository" do
      create_offer(repository: repo.id)
      second = create_offer(repository: repo.id, title: "refined")
      expect(second[:data][:deduped]).to be true
      expect(Ai::ImprovementRecommendation.by_repository(repo.id).count).to eq(1)
    end

    it "filters list_improvements to the repository by id or full_name" do
      other = create(:git_repository, account: account)
      create_offer(repository: repo.id)
      create_offer(repository: other.id, fingerprint: "code_lint|server/app/bar.rb|UnusedVar")

      by_id = tool.execute(params: { action: "list_improvements", repository: repo.id })
      by_name = tool.execute(params: { action: "list_improvements", repository: repo.full_name })

      expect(by_id[:data][:improvements].size).to eq(1)
      expect(by_id[:data][:improvements].map { |i| i[:repository_id] }).to all(eq(repo.id))
      expect(by_name[:data][:improvements].size).to eq(1)
    end
  end

  # ==========================================================================
  # Tier-2(c)/(e): create-path kill switch, revert action, gated autonomy
  # ==========================================================================
  describe "create_improvement kill switch (gate #3)" do
    it "is a no-op when the account kill switch is active" do
      allow_any_instance_of(Account).to receive(:ai_suspended?).and_return(true)

      result = create_offer
      expect(result[:data][:halted]).to be true
      expect(Ai::ImprovementRecommendation.count).to eq(0)
    end
  end

  describe "revert_improvement" do
    it "marks the promoted task reverted (works even while suspended)" do
      rec_id = create_offer[:data][:recommendation][:id]
      task_key = tool.execute(params: { action: "approve_improvement", recommendation_id: rec_id })[:data][:task_key]

      allow_any_instance_of(Account).to receive(:ai_suspended?).and_return(true) # undo must still work
      result = tool.execute(params: { action: "revert_improvement", recommendation_id: rec_id, reason: "regressed" })

      expect(result[:success]).to be true
      task = account.ai_ralph_loops.find_by(name: "dev-improve").ralph_tasks.find_by(task_key: task_key)
      expect(task.reverted?).to be true
      expect(task.revert_reason).to eq("regressed")
    end

    it "errors when no promoted task exists for the recommendation" do
      rec_id = create_offer[:data][:recommendation][:id] # created but never approved/promoted
      result = tool.execute(params: { action: "revert_improvement", recommendation_id: rec_id })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/No promoted task/)
    end
  end

  describe "enable_autonomy / disable_autonomy (gated)" do
    let(:agent) { create(:ai_agent, account: account, status: "active") }

    before do
      rec_id = create_offer[:data][:recommendation][:id]
      tool.execute(params: { action: "approve_improvement", recommendation_id: rec_id }) # bootstraps dev-improve loop
    end

    it "flips the dev-improve loop to autonomous push with a capped daily budget" do
      result = tool.execute(params: { action: "enable_autonomy", agent_id: agent.id, max_iterations_per_day: 5 })

      expect(result[:success]).to be true
      loop_record = account.ai_ralph_loops.find_by(name: "dev-improve").reload
      expect(loop_record.scheduling_mode).to eq("autonomous")
      expect(loop_record.default_agent_id).to eq(agent.id)
      expect(loop_record.schedule_config["max_iterations_per_day"]).to eq(5)
      expect(loop_record.next_scheduled_at).to be_present
    end

    it "refuses to enable autonomy while the kill switch is active" do
      allow_any_instance_of(Account).to receive(:ai_suspended?).and_return(true)
      result = tool.execute(params: { action: "enable_autonomy", agent_id: agent.id })

      expect(result[:data][:halted]).to be true
      expect(account.ai_ralph_loops.find_by(name: "dev-improve").reload.scheduling_mode).to eq("manual")
    end

    it "errors when the agent is not found or inactive" do
      result = tool.execute(params: { action: "enable_autonomy", agent_id: "ghost" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/agent not found/i)
    end

    it "disable_autonomy returns the loop to manual, paused" do
      tool.execute(params: { action: "enable_autonomy", agent_id: agent.id })
      result = tool.execute(params: { action: "disable_autonomy" })

      expect(result[:success]).to be true
      loop_record = account.ai_ralph_loops.find_by(name: "dev-improve").reload
      expect(loop_record.scheduling_mode).to eq("manual")
      expect(loop_record.schedule_paused).to be true
    end
  end

  describe "scoreboard (/improve status)" do
    it "returns the offer funnel and the ungameable metric" do
      create_offer # one pending offer
      result = tool.execute(params: { action: "scoreboard" })

      expect(result[:success]).to be true
      expect(result[:data][:discovered]).to eq(1)
      expect(result[:data][:metric]).to include(:net_improvement_velocity, :per_kind)
    end
  end
end
