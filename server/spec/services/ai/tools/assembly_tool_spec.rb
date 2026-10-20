# frozen_string_literal: true

require "rails_helper"

# platform.assemble_task — the MCP face of Ai::Assembly::Service. In the
# bootstrap floor (every agent and every thin loader has it), gated on
# ai.agents.read, and declared non-mutating: it persists its own assembly
# record and acts on no platform resource.
RSpec.describe Ai::Tools::AssemblyTool do
  let!(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:tool) { described_class.new(account: account, user: user) }

  before do
    use_recorded_skill_embeddings!
    seed_with_baseline!(Rails.root.join("db", "seeds", "ai_capability_skills_seed.rb"))
  end

  it "is registered as assemble_task, in the bootstrap floor, read-gated and declared non-mutating" do
    expect(Ai::Tools::PlatformApiToolRegistry.all_tools["assemble_task"]).to eq("Ai::Tools::AssemblyTool")
    expect(Ai::Tools::BootstrapVerbs::ACTIONS).to include("assemble_task")
    expect(Ai::ClaudeExport::ThinLoader::BOOTSTRAP_ACTIONS).to include("assemble_task")
    expect(described_class::REQUIRED_PERMISSION).to eq("ai.agents.read")
    expect(described_class.declared_actions.fetch("assemble_task")[:mutating]).to be false
    expect(described_class.action_definitions.keys).to eq([ "assemble_task" ])
    expect(described_class.family_for("assemble_task")).to be_present
  end

  it "assembles a task for a roster agent" do
    result = tool.execute(params: { action: "assemble_task", agent_slug: "platform-engineer", context: "claude_code",
                                    task: "Work a dev-improve task that adds a migration and a spec" })

    expect(result[:success]).to be true
    data = result[:data]
    expect(data).to include(:assembly_id, :skills, :learnings, :tier, :model, :effort, :floor_reason, :uncovered, :routing_decision_id)
    expect(data[:skills]).not_to be_empty
  end

  it "fetches the stored assembly when only assembly_id is given" do
    first = tool.execute(params: { action: "assemble_task", agent_slug: "platform-engineer",
                                   task: "Work a dev-improve task that adds a migration and a spec" })[:data]

    again = tool.execute(params: { action: "assemble_task", agent_slug: "platform-engineer", assembly_id: first[:assembly_id] })

    expect(again[:success]).to be true
    expect(again[:data][:assembly_id]).to eq(first[:assembly_id])
  end

  it "defaults the context to claude_code" do
    data = tool.execute(params: { action: "assemble_task", agent_slug: "platform-engineer",
                                  task: "Work a dev-improve task that adds a migration and a spec" })[:data]

    expect(data[:model]).to be_in(%w[haiku sonnet opus fable])
  end

  it "reports refusals as errors, not exceptions" do
    expect(tool.execute(params: { action: "assemble_task", agent_slug: "nobody", task: "x" })).to include(success: false)
    expect(tool.execute(params: { action: "assemble_task", agent_slug: "platform-engineer" })).to include(success: false)
  end

  it "refuses a caller without ai.agents.read" do
    denied = described_class.new(account: account, user: create(:user, account: account, permissions: []))

    result = denied.execute(params: { action: "assemble_task", agent_slug: "platform-engineer", task: "anything" })

    expect(result[:success]).to be false
    expect(result[:error]).to include("ai.agents.read")
  end
end
