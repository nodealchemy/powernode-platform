# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::SkillService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  subject(:service) { described_class.new(account: account) }

  describe '#list_skills' do
    let!(:skill1) { create(:ai_skill, account: account, name: "Skill Alpha", category: "productivity") }
    let!(:skill2) { create(:ai_skill, account: account, name: "Skill Beta", category: "sales") }
    let!(:system_skill) { create(:ai_skill, :system_skill, account: nil, name: "System Skill", category: "productivity") }

    it 'returns skills for the account including system skills' do
      results = service.list_skills

      ids = results.map(&:id)
      expect(ids).to include(skill1.id, skill2.id, system_skill.id)
    end

    it 'filters by category' do
      results = service.list_skills(filters: { category: "productivity" })

      results.each do |skill|
        expect(skill.category).to eq("productivity")
      end
    end

    it 'filters by status' do
      create(:ai_skill, account: account, status: "draft", category: "productivity")

      results = service.list_skills(filters: { status: "draft" })

      results.each do |skill|
        expect(skill.status).to eq("draft")
      end
    end

    it 'filters by enabled status' do
      disabled = create(:ai_skill, :disabled, account: account, category: "productivity")

      results = service.list_skills(filters: { enabled: "true" })

      ids = results.map(&:id)
      expect(ids).not_to include(disabled.id)
    end

    it 'filters by search term' do
      results = service.list_skills(filters: { search: "Alpha" })

      expect(results.map(&:id)).to include(skill1.id)
      expect(results.map(&:id)).not_to include(skill2.id)
    end

    it 'orders system skills first, then by name' do
      results = service.list_skills

      system_indices = results.each_with_index.select { |s, _| s.is_system }.map(&:last)
      non_system_indices = results.each_with_index.reject { |s, _| s.is_system }.map(&:last)

      if system_indices.any? && non_system_indices.any?
        expect(system_indices.max).to be < non_system_indices.min
      end
    end
  end

  describe '#find_skill' do
    let!(:skill) { create(:ai_skill, account: account, category: "productivity") }

    it 'finds a skill by id' do
      found = service.find_skill(skill_id: skill.id)
      expect(found).to eq(skill)
    end

    it 'raises NotFoundError for non-existent skill' do
      expect {
        service.find_skill(skill_id: SecureRandom.uuid)
      }.to raise_error(Ai::SkillService::NotFoundError, "Skill not found")
    end
  end

  describe '#create_skill' do
    let(:attributes) do
      {
        name: "New Skill",
        description: "A new skill",
        category: "productivity",
        status: "active",
        version: "1.0.0"
      }
    end

    it 'creates a skill with valid attributes' do
      skill = service.create_skill(attributes: attributes)

      expect(skill).to be_persisted
      expect(skill.name).to eq("New Skill")
      expect(skill.account).to eq(account)
    end

    it 'assigns knowledge base when provided' do
      kb = create(:ai_knowledge_base, account: account)

      skill = service.create_skill(attributes: attributes, knowledge_base_id: kb.id)

      expect(skill.ai_knowledge_base_id).to eq(kb.id)
    end

    it 'raises ValidationError for invalid attributes' do
      expect {
        service.create_skill(attributes: { name: nil })
      }.to raise_error(Ai::SkillService::ValidationError)
    end
  end

  describe '#update_skill' do
    let!(:skill) { create(:ai_skill, account: account, name: "Original", category: "productivity") }

    it 'updates skill attributes' do
      updated = service.update_skill(skill_id: skill.id, attributes: { name: "Updated" })

      expect(updated.name).to eq("Updated")
    end

    it 'raises ValidationError for system skills' do
      system_skill = create(:ai_skill, :system_skill, account: nil, category: "productivity")

      expect {
        service.update_skill(skill_id: system_skill.id, attributes: { name: "Changed" })
      }.to raise_error(Ai::SkillService::ValidationError, "Cannot modify system skills")
    end

    it 'raises NotFoundError for non-existent skill' do
      expect {
        service.update_skill(skill_id: SecureRandom.uuid, attributes: { name: "X" })
      }.to raise_error(Ai::SkillService::NotFoundError)
    end
  end

  describe '#delete_skill' do
    let!(:skill) { create(:ai_skill, account: account, category: "productivity") }

    it 'deletes a non-system skill' do
      expect {
        service.delete_skill(skill_id: skill.id)
      }.to change(Ai::Skill, :count).by(-1)
    end

    it 'raises ValidationError for system skills' do
      system_skill = create(:ai_skill, :system_skill, account: nil, category: "productivity")

      expect {
        service.delete_skill(skill_id: system_skill.id)
      }.to raise_error(Ai::SkillService::ValidationError, "Cannot delete system skills")
    end
  end

  describe '#toggle_skill' do
    let!(:skill) { create(:ai_skill, account: account, is_enabled: true, category: "productivity") }

    it 'activates a skill' do
      disabled = create(:ai_skill, :disabled, account: account, category: "productivity")
      result = service.toggle_skill(skill_id: disabled.id, enabled: true)

      expect(result.is_enabled).to be true
    end

    it 'deactivates a skill' do
      result = service.toggle_skill(skill_id: skill.id, enabled: false)

      expect(result.is_enabled).to be false
    end
  end

  describe '#assign_to_agent' do
    let!(:skill) { create(:ai_skill, account: account, category: "productivity") }
    let(:provider) { create(:ai_provider, account: account) }
    let(:agent) { create(:ai_agent, account: account, provider: provider, creator: user) }

    it 'assigns a skill to an agent' do
      assignment = service.assign_to_agent(skill_id: skill.id, agent_id: agent.id)

      expect(assignment).to be_a(Ai::AgentSkill)
      expect(assignment.ai_agent_id).to eq(agent.id)
      expect(assignment.ai_skill_id).to eq(skill.id)
    end

    it 'raises NotFoundError for non-existent agent' do
      expect {
        service.assign_to_agent(skill_id: skill.id, agent_id: SecureRandom.uuid)
      }.to raise_error(Ai::SkillService::NotFoundError, "Agent not found")
    end
  end

  describe '#remove_from_agent' do
    let!(:skill) { create(:ai_skill, account: account, category: "productivity") }
    let(:provider) { create(:ai_provider, account: account) }
    let(:agent) { create(:ai_agent, account: account, provider: provider, creator: user) }

    it 'removes a skill assignment from an agent' do
      create(:ai_agent_skill, agent: agent, skill: skill)

      expect {
        service.remove_from_agent(skill_id: skill.id, agent_id: agent.id)
      }.to change(Ai::AgentSkill, :count).by(-1)
    end

    it 'raises NotFoundError when assignment does not exist' do
      expect {
        service.remove_from_agent(skill_id: skill.id, agent_id: agent.id)
      }.to raise_error(Ai::SkillService::NotFoundError, "Agent-skill assignment not found")
    end
  end

  describe '#agent_skills' do
    let(:provider) { create(:ai_provider, account: account) }
    let(:agent) { create(:ai_agent, account: account, provider: provider, creator: user) }
    let!(:skill) { create(:ai_skill, account: account, category: "productivity") }

    it 'returns skills for an agent ordered by priority' do
      create(:ai_agent_skill, agent: agent, skill: skill, priority: 1)

      result = service.agent_skills(agent_id: agent.id)

      expect(result.size).to eq(1)
    end

    it 'raises NotFoundError for non-existent agent' do
      expect {
        service.agent_skills(agent_id: SecureRandom.uuid)
      }.to raise_error(Ai::SkillService::NotFoundError, "Agent not found")
    end
  end

  describe '#skill_agents' do
    let!(:skill) { create(:ai_skill, account: account, category: "productivity") }
    let(:provider) { create(:ai_provider, account: account) }
    let(:agent) { create(:ai_agent, account: account, provider: provider, creator: user) }

    it 'returns agents for a skill' do
      create(:ai_agent_skill, agent: agent, skill: skill)

      result = service.skill_agents(skill_id: skill.id)

      expect(result.map(&:id)).to include(agent.id)
    end
  end
end
