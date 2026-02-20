# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::LifecycleService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account) }
  subject(:service) { described_class.new(account) }

  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Agent).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  describe "#create_proposal" do
    it "creates a proposal in draft status" do
      proposal = service.create_proposal(attributes: {
        name: "Code Review Automation",
        description: "Automate code reviews",
        category: "productivity"
      })

      expect(proposal).to be_a(Ai::SkillProposal)
      expect(proposal).to be_persisted
      expect(proposal.status).to eq("draft")
      expect(proposal.name).to eq("Code Review Automation")
      expect(proposal.account).to eq(account)
    end

    it "raises RecordInvalid on validation failure" do
      expect {
        service.create_proposal(attributes: { name: nil })
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "assigns agent and user references when provided" do
      proposal = service.create_proposal(attributes: {
        name: "Agent Proposed Skill",
        description: "Proposed by an agent",
        category: "productivity",
        proposed_by_agent_id: agent.id,
        proposed_by_user_id: user.id
      })

      expect(proposal.proposed_by_agent_id).to eq(agent.id)
      expect(proposal.proposed_by_user_id).to eq(user.id)
    end
  end

  describe "#submit_proposal" do
    let!(:proposal) { create(:ai_skill_proposal, :proposed, account: account, status: "draft") }

    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_lifecycle_auto_create, account).and_return(false)
    end

    it "transitions a draft proposal to proposed status" do
      # Reset to draft since factory may have set it otherwise
      proposal.update_column(:status, "draft")

      result = service.submit_proposal(proposal_id: proposal.id)

      expect(result).to be_a(Ai::SkillProposal)
      expect(result.status).to eq("proposed")
    end

    it "raises RecordNotFound for non-existent proposal" do
      expect {
        service.submit_proposal(proposal_id: SecureRandom.uuid)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    context "with auto-approval enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_lifecycle_auto_create, account).and_return(true)
      end

      it "auto-approves proposals from trusted agents" do
        proposal.update_columns(status: "draft", trust_tier_at_proposal: "trusted")

        # Stub skill creation dependencies
        mock_skill_service = instance_double(Ai::SkillService)
        mock_skill = create(:ai_skill, account: account, name: "Auto Created Skill")
        allow(Ai::SkillService).to receive(:new).and_return(mock_skill_service)
        allow(mock_skill_service).to receive(:create_skill).and_return(mock_skill)

        mock_bridge = instance_double(Ai::SkillGraph::BridgeService)
        allow(Ai::SkillGraph::BridgeService).to receive(:new).and_return(mock_bridge)
        allow(mock_bridge).to receive(:sync_skill)
        allow(mock_bridge).to receive(:create_skill_edge)

        result = service.submit_proposal(proposal_id: proposal.id)

        expect(result.status).to eq("created")
        expect(result.auto_approved).to be true
      end

      it "does not auto-approve proposals from supervised agents" do
        proposal.update_columns(status: "draft", trust_tier_at_proposal: "supervised")

        result = service.submit_proposal(proposal_id: proposal.id)

        expect(result.status).to eq("proposed")
      end
    end
  end

  describe "#approve_proposal" do
    let!(:proposal) { create(:ai_skill_proposal, account: account, status: "proposed") }

    it "approves a proposed proposal with a reviewer" do
      result = service.approve_proposal(proposal_id: proposal.id, reviewer: user)

      expect(result).to be_a(Ai::SkillProposal)
      expect(result.status).to eq("approved")
      expect(result.reviewed_by).to eq(user)
    end

    it "approves without reviewer (auto-approval path)" do
      result = service.approve_proposal(proposal_id: proposal.id, reviewer: nil)

      expect(result).to be_a(Ai::SkillProposal)
      expect(result.status).to eq("approved")
    end

    it "raises when proposal is not in proposed status" do
      proposal.update_column(:status, "draft")

      expect {
        service.approve_proposal(proposal_id: proposal.id, reviewer: user)
      }.to raise_error(RuntimeError, /Can only approve proposed proposals/)
    end
  end

  describe "#reject_proposal" do
    let!(:proposal) { create(:ai_skill_proposal, account: account, status: "proposed") }

    it "rejects a proposed proposal with reason" do
      result = service.reject_proposal(proposal_id: proposal.id, reviewer: user, reason: "Duplicate functionality")

      expect(result).to be_a(Ai::SkillProposal)
      expect(result.status).to eq("rejected")
      expect(result.rejection_reason).to eq("Duplicate functionality")
    end

    it "raises for non-proposed proposals" do
      proposal.update_column(:status, "approved")

      expect {
        service.reject_proposal(proposal_id: proposal.id, reviewer: user, reason: "N/A")
      }.to raise_error(RuntimeError, /Can only reject proposed proposals/)
    end
  end

  describe "#create_skill_from_proposal" do
    let!(:proposal) do
      create(:ai_skill_proposal, :approved,
        account: account,
        name: "New Skill From Proposal",
        description: "A great new skill",
        category: "productivity"
      )
    end
    let(:mock_bridge) { instance_double(Ai::SkillGraph::BridgeService) }

    before do
      allow(Ai::SkillGraph::BridgeService).to receive(:new).and_return(mock_bridge)
      allow(mock_bridge).to receive(:sync_skill)
      allow(mock_bridge).to receive(:create_skill_edge)
    end

    it "creates a skill from an approved proposal" do
      result = service.create_skill_from_proposal(proposal_id: proposal.id)

      expect(result).to be_a(Hash)
      expect(result[:skill]).to be_a(Ai::Skill)
      expect(result[:skill]).to be_persisted
      expect(result[:skill].name).to eq("New Skill From Proposal")
      expect(result[:skill].account).to eq(account)
      expect(result[:proposal]).to be_a(Ai::SkillProposal)
    end

    it "creates an initial version for the skill" do
      result = service.create_skill_from_proposal(proposal_id: proposal.id)
      skill = result[:skill]

      expect(skill.versions.count).to eq(1)
      version = skill.versions.first
      expect(version.version).to eq("1.0.0")
      expect(version.is_active).to be true
      expect(version.change_type).to eq("manual")
    end

    it "marks the proposal as created" do
      service.create_skill_from_proposal(proposal_id: proposal.id)
      proposal.reload

      expect(proposal.status).to eq("created")
      expect(proposal.created_skill).to be_present
    end

    it "syncs to knowledge graph via bridge service" do
      expect(mock_bridge).to receive(:sync_skill).once

      service.create_skill_from_proposal(proposal_id: proposal.id)
    end

    it "creates dependency edges from suggested dependencies" do
      target_skill = create(:ai_skill, account: account)
      proposal.update!(suggested_dependencies: [
        { "skill_id" => target_skill.id, "relation_type" => "requires", "confidence" => 0.8 }
      ])

      expect(mock_bridge).to receive(:create_skill_edge).once

      service.create_skill_from_proposal(proposal_id: proposal.id)
    end

    it "raises for non-approved proposals" do
      proposal.update_column(:status, "proposed")

      expect {
        service.create_skill_from_proposal(proposal_id: proposal.id)
      }.to raise_error(RuntimeError, /Proposal must be approved/)
    end
  end

  describe "#research_and_propose" do
    let(:mock_research) { instance_double(Ai::SkillGraph::ResearchService) }

    before do
      allow(Ai::SkillGraph::ResearchService).to receive(:new).and_return(mock_research)
      allow(mock_research).to receive(:research).and_return({
        topic: "testing automation",
        findings: { knowledge_graph: [], knowledge_bases: [], mcp: [], federation: [] },
        total_findings: 0
      })
      allow(mock_research).to receive(:detect_overlaps).and_return({ overlaps: [], count: 0 })
      allow(mock_research).to receive(:suggest_dependencies).and_return([])
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_lifecycle_auto_create, account).and_return(false)
    end

    it "creates a proposal from research results" do
      result = service.research_and_propose(topic: "testing automation", requesting_user: user)

      expect(result).to be_a(Ai::SkillProposal)
      expect(result.name).to eq("testing automation")
      expect(result.status).to eq("proposed")
      expect(result.research_report).to be_a(Hash)
    end

    it "includes overlap analysis in the proposal" do
      allow(mock_research).to receive(:detect_overlaps).and_return({
        overlaps: [{ skill_id: "abc", similarity: 0.85, severity: "high_overlap" }],
        count: 1
      })

      result = service.research_and_propose(topic: "overlapping skill")

      expect(result.overlap_analysis).to be_a(Hash)
      expect(result.overlap_analysis["count"] || result.overlap_analysis[:count]).to eq(1)
    end

    it "returns error hash on failure" do
      allow(mock_research).to receive(:research).and_raise(StandardError, "research failure")

      result = service.research_and_propose(topic: "failing topic")

      expect(result).to be_a(Hash)
      expect(result[:error]).to eq("research failure")
    end
  end

  describe "#list_proposals" do
    before do
      create(:ai_skill_proposal, account: account, status: "draft", category: "productivity")
      create(:ai_skill_proposal, account: account, status: "proposed", category: "sales")
      create(:ai_skill_proposal, account: account, status: "approved", category: "productivity")
    end

    it "returns all proposals for the account" do
      result = service.list_proposals
      expect(result.count).to eq(3)
    end

    it "filters by status" do
      result = service.list_proposals(filters: { status: "proposed" })
      expect(result.count).to eq(1)
      expect(result.first.status).to eq("proposed")
    end

    it "filters by category" do
      result = service.list_proposals(filters: { category: "productivity" })
      expect(result.count).to eq(2)
    end
  end
end
