# frozen_string_literal: true

require "rails_helper"

# R1 of the 0.3.0 roster activation: a global canonical agent is a read-only
# template, so a runtime writer that attributes to an agent refuses a global
# row with a stated reason and writes nothing. There is no silent fallback.
RSpec.describe Ai::Agents::ShadowWriteGuard do
  let(:account) { create(:account) }
  let(:global_agent) { create(:ai_agent, :global, is_system: true, name: "Platform Engineer", slug: "platform-engineer") }
  let(:shadow) { create(:ai_agent, account: account, name: "Platform Engineer Shadow") }

  def expect_refusal(writer)
    expect { yield }.to raise_error(Ai::Agents::GlobalRowRefused) { |e|
      expect(e.reason).to eq("global_canonical_row")
      expect(e.details).to include(writer: writer, agent_slug: "platform-engineer")
      expect(e.message).to include("platform-engineer", "read-only template")
    }
  end

  describe ".refuse_global!" do
    it "raises a structured refusal for a global agent record, or its id" do
      expect_refusal("w") { described_class.refuse_global!(global_agent, writer: "w") }
      expect_refusal("w") { described_class.refuse_global!(global_agent.id, writer: "w") }
    end

    it "passes an account-scoped agent, an unknown id and nil" do
      expect(described_class.refuse_global!(shadow, writer: "w")).to eq(shadow)
      expect { described_class.refuse_global!(SecureRandom.uuid, writer: "w") }.not_to raise_error
      expect { described_class.refuse_global!(nil, writer: "w") }.not_to raise_error
    end
  end

  describe "agent memory writes (Ai::Memory::AgentManagedMemoryService)" do
    it "refuses remember, forget and reflect for a global agent and creates no pool" do
      service = Ai::Memory::AgentManagedMemoryService.new(account: account, agent: global_agent)

      expect_refusal("Ai::Memory::AgentManagedMemoryService#remember") { service.remember(key: "k", value: "v") }
      expect_refusal("Ai::Memory::AgentManagedMemoryService#forget") { service.forget(key: "k") }
      expect_refusal("Ai::Memory::AgentManagedMemoryService#reflect") { service.reflect }
      expect(Ai::MemoryPool.where(owner_agent_id: global_agent.id)).to be_empty
    end

    it "still remembers for the account's shadow" do
      result = Ai::Memory::AgentManagedMemoryService.new(account: account, agent: shadow).remember(key: "k", value: "v")
      expect(result[:stored]).to be(true)
    end
  end

  describe "learning writes that name an agent (Ai::Learning::CompoundLearningService)" do
    let(:service) { Ai::Learning::CompoundLearningService.new(account: account) }

    it "refuses a learning whose source agent is a global row, and stores nothing" do
      result = nil
      expect {
        result = service.store_learning_with_outcome({ content: "a lesson", category: "discovery", source_agent_id: global_agent.id })
      }.not_to change(Ai::CompoundLearning, :count)

      expect(result[:outcome]).to eq(:refused)
      expect(result[:reason]).to eq("global_canonical_row")
      expect(result[:errors].join).to include("read-only template")
    end

    it "also refuses through the agent_id alias" do
      result = service.store_learning_with_outcome({ content: "a lesson", category: "discovery", agent_id: global_agent.id })
      expect(result[:outcome]).to eq(:refused)
    end

    it "stores a learning that names the shadow" do
      result = service.store_learning_with_outcome({ content: "a lesson from the shadow", category: "discovery", source_agent_id: shadow.id })
      expect(result[:outcome]).to eq(:created)
    end
  end

  describe "memory router writes that name the agent (Ai::Memory::RouterService)" do
    let(:router) { Ai::Memory::RouterService.new(account: account, agent: global_agent) }

    it "refuses every tier for a global agent with a structured result and stores nothing" do
      %w[working short_term long_term shared].each do |tier|
        result = router.write(key: "k", value: "v", tier: tier, session_id: "s")
        expect(result).to include(success: false, refused: true, reason: "global_canonical_row")
        expect(result[:details]).to include(writer: "Ai::Memory::RouterService#write", agent_slug: "platform-engineer")
      end
      expect(Ai::CompoundLearning.count).to eq(0)
      expect(Ai::SharedKnowledge.count).to eq(0)
      expect(Ai::AgentShortTermMemory.count).to eq(0)
    end
  end

  describe "memory consolidation (Ai::Memory::MaintenanceService)" do
    it "refuses to consolidate a global agent's short-term memory into long-term learnings" do
      service = Ai::Memory::MaintenanceService.new(account: account)

      expect_refusal("Ai::Memory::MaintenanceService#consolidate_short_term") do
        service.consolidate_short_term(agent: global_agent)
      end
      expect(Ai::CompoundLearning.count).to eq(0)
    end
  end

  describe "reflexion (Ai::Learning::ReflexionService)" do
    it "logs a refusal and writes no reflexion learning against a global agent's execution" do
      execution = Struct.new(:ai_agent, :id).new(global_agent, SecureRandom.uuid)
      service = Ai::Learning::ReflexionService.new(account: account)
      allow(service).to receive(:should_reflect?).and_return(true)

      allow(Rails.logger).to receive(:warn)

      expect(service.reflect_on_failure(execution)).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/\[Reflexion\] Refused \(global_canonical_row\).*platform-engineer/)
      expect(Ai::CompoundLearning.count).to eq(0)
    end
  end

  describe "Ralph iteration learnings (Ai::Ralph::ExecutionService::PrdAndBroadcasting)" do
    let(:host_class) do
      Class.new do
        include Ai::Ralph::ExecutionService::PrdAndBroadcasting

        attr_reader :account, :ralph_loop

        def initialize(account, ralph_loop)
          @account = account
          @ralph_loop = ralph_loop
        end
      end
    end

    it "writes no pool entry and no learning when the loop's default agent is a global row" do
      loop_double = Struct.new(:default_agent).new(global_agent)
      allow(Rails.logger).to receive(:warn)

      expect { host_class.new(account, loop_double).send(:store_iteration_learnings, "Discovery: a thing worth keeping") }
        .not_to change { [ Ai::CompoundLearning.count, Ai::MemoryPool.count ] }
      expect(Rails.logger).to have_received(:warn).with(/\[Ralph\] Learning storage failed: Refused:.*platform-engineer/)
    end
  end
end
