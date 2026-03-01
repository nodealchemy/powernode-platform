# frozen_string_literal: true

require "rails_helper"

RSpec.describe A2a::SkillRegistry do
  describe ".platform_skills" do
    subject(:skills) { described_class.platform_skills }

    it "returns an array of skills" do
      expect(skills).to be_an(Array)
      expect(skills).not_to be_empty
    end

    it "includes workflow skills" do
      workflow_skills = skills.select { |s| s[:category] == "workflows" }
      expect(workflow_skills).not_to be_empty

      skill_ids = workflow_skills.map { |s| s[:id] }
      expect(skill_ids).to include("workflows.list", "workflows.execute")
    end

    it "includes agent skills" do
      agent_skills = skills.select { |s| s[:category] == "agents" }
      expect(agent_skills).not_to be_empty

      skill_ids = agent_skills.map { |s| s[:id] }
      expect(skill_ids).to include("agents.list", "agents.execute")
    end

    it "includes devops skills" do
      devops_skills = skills.select { |s| s[:category] == "devops" }
      expect(devops_skills).not_to be_empty
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
      skill = described_class.find_skill("workflows.list")

      expect(skill).to be_present
      expect(skill[:name]).to eq("List Workflows")
    end

    it "returns nil for unknown skill" do
      skill = described_class.find_skill("unknown.skill")
      expect(skill).to be_nil
    end
  end

  describe ".skills_by_category" do
    it "returns skills in a category" do
      skills = described_class.skills_by_category("workflows")

      expect(skills).not_to be_empty
      expect(skills.all? { |s| s[:category] == "workflows" }).to be true
    end

    it "returns empty array for unknown category" do
      skills = described_class.skills_by_category("unknown")
      expect(skills).to be_empty
    end
  end

  describe ".register_skill" do
    after do
      described_class.reload!
    end

    it "registers a new skill" do
      described_class.register_skill(
        id: "custom.skill",
        name: "Custom Skill",
        description: "A custom skill",
        category: "custom",
        handler: "CustomHandler.execute"
      )

      skill = described_class.find_skill("custom.skill")
      expect(skill).to be_present
      expect(skill[:name]).to eq("Custom Skill")
    end
  end

  describe ".reload!" do
    it "reloads the skill registry" do
      original_count = described_class.platform_skills.count

      described_class.register_skill(
        id: "temp.skill",
        name: "Temp",
        description: "Temp",
        category: "temp",
        handler: "Temp.execute"
      )

      expect(described_class.platform_skills.count).to eq(original_count + 1)

      described_class.reload!

      expect(described_class.platform_skills.count).to eq(original_count)
    end
  end
end
