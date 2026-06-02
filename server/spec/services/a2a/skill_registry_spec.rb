# frozen_string_literal: true

require "rails_helper"

RSpec.describe A2a::SkillRegistry do
  describe ".platform_skills" do
    subject(:skills) { described_class.platform_skills }

    it "returns an array of skills" do
      expect(skills).to be_an(Array)
      expect(skills).not_to be_empty
    end

    it "includes agent skills" do
      agent_skills = skills.select { |s| s[:category] == "agents" }
      expect(agent_skills).not_to be_empty

      skill_ids = agent_skills.map { |s| s[:id] }
      expect(skill_ids).to include("agents.list", "agents.execute")
    end

    it "includes memory skills" do
      memory_skills = skills.select { |s| s[:category] == "memory" }
      expect(memory_skills).not_to be_empty
    end

    it "includes mcp skills" do
      mcp_skills = skills.select { |s| s[:category] == "mcp" }
      expect(mcp_skills).not_to be_empty
    end

    it "has valid skill structure" do
      skill = skills.first

      expect(skill).to include(
        :id,
        :name,
        :description,
        :category,
        :input_schema,
        :output_schema,
        :tags,
        :handler
      )
    end
  end

  describe ".find_skill" do
    it "finds skill by id" do
      skill = described_class.find_skill("agents.list")

      expect(skill).to be_present
      expect(skill[:name]).to eq("List Agents")
    end

    it "returns nil for unknown skill" do
      skill = described_class.find_skill("unknown.skill")
      expect(skill).to be_nil
    end
  end

  describe ".reload!" do
    it "rebuilds the platform skill set" do
      original_count = described_class.platform_skills.count

      # Inject a transient skill directly, then confirm reload! rebuilds it away
      described_class.platform_skills << { id: "temp.skill", name: "Temp" }
      expect(described_class.platform_skills.count).to eq(original_count + 1)

      described_class.reload!

      expect(described_class.platform_skills.count).to eq(original_count)
    end
  end
end
