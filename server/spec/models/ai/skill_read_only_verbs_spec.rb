# frozen_string_literal: true

require "rails_helper"

# A skill that attests it is read-only (manifest.read_only / gate_category read) is
# what a read-only agent may be assembled with and what verb risk treats as calm.
# The seed gate enforces that for seeded batches; an account-cloned or hand-made
# capability skill reaches the table through Ai::Skill#save, so the same rule
# (Ai::Skills::ReadOnlyVerbs) applies there.
RSpec.describe Ai::Skill, "read-only skills name no writing verb" do
  def skill_with(verbs, **manifest)
    entry = conforming_capability_entry(slug: "ro-clone", domain: "review")
    entry["metadata"]["manifest"].merge!({ "verbs" => verbs, "gate_category" => "read", "read_only" => true }.merge(manifest.stringify_keys))
    described_class.new(slug: entry["slug"], name: entry["name"], description: entry["description"], category: entry["category"],
                        tags: entry["tags"], system_prompt: entry["system_prompt"], metadata: entry["metadata"], is_system: false,
                        account: create(:account))
  end

  it "rejects a read-only skill that names a mutating verb" do
    skill = skill_with(%w[search_knowledge create_knowledge])

    expect(skill).not_to be_valid
    expect(skill.errors[:metadata].join).to include("create_knowledge").and include("mutating")
  end

  it "rejects a read-only skill that names a registered verb with no declared action" do
    stub_const("UndeclaredReadTool", Class.new)
    tools = Ai::Tools::PlatformApiToolRegistry.all_tools.merge("undeclared_read_verb" => "UndeclaredReadTool")
    allow(Ai::Tools::PlatformApiToolRegistry).to receive(:all_tools).and_return(tools)

    expect(skill_with(%w[undeclared_read_verb])).not_to be_valid
  end

  it "accepts read verbs and the self-report verb" do
    expect(skill_with(%w[search_knowledge query_learnings record_agent_execution])).to be_valid
  end

  it "leaves a skill that declares a mutate gate category alone" do
    expect(skill_with(%w[create_knowledge], gate_category: "mutate", read_only: false)).to be_valid
  end

  it "does not reject a verb the registry does not know (an extension that is not loaded)" do
    expect(skill_with(%w[search_knowledge not_loaded_extension_verb])).to be_valid
  end

  it "is one rule shared with the seed gate" do
    expect(Ai::Skills::SeedGate.instance_method(:read_skill_errors).source_location.first).to end_with("seed_gate.rb")
    expect(File.read(Rails.root.join("app/services/ai/skills/seed_gate.rb"))).to include("ReadOnlyVerbs")
  end
end
