# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Teams::ConfigurationService, type: :service do
  let(:account) { create(:account) }
  let(:team) { create(:ai_agent_team, account: account) }

  subject(:service) { described_class.new(account: account) }

  describe '#list_roles' do
    let!(:role) { Ai::TeamRole.create!(account: account, agent_team: team, role_name: 'dev', role_type: 'worker') }

    it 'returns roles for the team' do
      result = service.list_roles(team.id)
      expect(result).to include(role)
    end
  end

  describe '#create_role' do
    it 'creates a role with valid params' do
      params = { role_name: 'Developer', role_type: 'worker', role_description: 'Writes code' }
      role = service.create_role(team.id, params)
      expect(role).to be_persisted
      expect(role.role_name).to eq('Developer')
      expect(role.role_type).to eq('worker')
    end

    # Regression: `can_escalate: params[:can_escalate] || true` forced false -> true,
    # so a role meant to be barred from escalation was silently created escalation-capable
    # (TeamRole#can_escalate_to? returns false unless can_escalate).
    it 'honors an explicit can_escalate: false' do
      role = service.create_role(team.id, { role_name: 'Locked', role_type: 'worker', can_escalate: false })
      expect(role.can_escalate).to be false
    end

    it 'defaults can_escalate to true when unspecified' do
      role = service.create_role(team.id, { role_name: 'Default', role_type: 'worker' })
      expect(role.can_escalate).to be true
    end
  end

  describe '#update_role' do
    let!(:role) { Ai::TeamRole.create!(account: account, agent_team: team, role_name: 'dev', role_type: 'worker') }

    it 'updates the role' do
      result = service.update_role(team.id, role.id, { role_name: 'Senior Dev' })
      expect(result.role_name).to eq('Senior Dev')
    end
  end

  describe '#assign_agent_to_role' do
    let!(:role) { Ai::TeamRole.create!(account: account, agent_team: team, role_name: 'dev', role_type: 'worker') }
    let!(:agent) { create(:ai_agent, account: account) }

    it 'assigns agent to the role' do
      result = service.assign_agent_to_role(team.id, role.id, agent.id)
      expect(result.ai_agent).to eq(agent)
    end
  end

  describe '#delete_role' do
    let!(:role) { Ai::TeamRole.create!(account: account, agent_team: team, role_name: 'dev', role_type: 'worker') }

    it 'destroys the role' do
      service.delete_role(team.id, role.id)
      expect(Ai::TeamRole.exists?(role.id)).to be false
    end
  end

  describe '#list_channels' do
    let!(:channel) { Ai::TeamChannel.create!(agent_team: team, name: 'General', channel_type: 'broadcast') }

    it 'returns channels for the team' do
      result = service.list_channels(team.id)
      expect(result).to include(channel)
    end
  end

  describe '#create_channel' do
    it 'creates a channel with valid params' do
      channel = service.create_channel(team.id, { name: 'Tasks', channel_type: 'task', description: 'Task channel' })
      expect(channel).to be_persisted
      expect(channel.name).to eq('Tasks')
      expect(channel.channel_type).to eq('task')
    end

    it 'raises RecordNotFound for invalid participant_roles' do
      expect {
        service.create_channel(team.id, { name: 'Bad', participant_roles: [SecureRandom.uuid] })
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#get_channel' do
    let!(:channel) { Ai::TeamChannel.create!(agent_team: team, name: 'General', channel_type: 'broadcast') }

    it 'returns channel by ID' do
      result = service.get_channel(team.id, channel.id)
      expect(result).to eq(channel)
    end

    it 'raises RecordNotFound for invalid channel ID' do
      expect { service.get_channel(team.id, SecureRandom.uuid) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#update_channel' do
    let!(:channel) { Ai::TeamChannel.create!(agent_team: team, name: 'Old Name', channel_type: 'broadcast') }

    it 'updates allowed fields' do
      result = service.update_channel(team.id, channel.id, { name: 'New Name', description: 'Updated' })
      expect(result.name).to eq('New Name')
      expect(result.description).to eq('Updated')
    end

    it 'raises for non-existent channel' do
      expect {
        service.update_channel(team.id, SecureRandom.uuid, { name: 'X' })
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#delete_channel' do
    let!(:channel) { Ai::TeamChannel.create!(agent_team: team, name: 'Doomed', channel_type: 'direct') }

    it 'destroys the channel' do
      service.delete_channel(team.id, channel.id)
      expect(Ai::TeamChannel.exists?(channel.id)).to be false
    end

    it 'raises for non-existent channel' do
      expect {
        service.delete_channel(team.id, SecureRandom.uuid)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#list_templates' do
    it 'returns templates' do
      result = service.list_templates
      expect(result).to respond_to(:each)
    end
  end

  describe '#get_template' do
    it 'returns the account\'s own template' do
      template = create(:ai_team_template, account: account)
      expect(service.get_template(template.id)).to eq(template)
    end

    it 'returns a global (platform) template' do
      template = create(:ai_team_template, :system_template)
      expect(service.get_template(template.id)).to eq(template)
    end

    it 'does not return another account\'s custom template (IDOR)' do
      other_account = create(:account)
      foreign_template = create(:ai_team_template, account: other_account)

      expect {
        service.get_template(foreign_template.id)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#analyze_composition' do
    it 'returns composition analysis for a team' do
      result = service.analyze_composition(team)
      expect(result).to include(:team_id, :team_name, :members_count, :skill_coverage, :role_balance, :coverage_score, :health)
    end

    context 'when the team agents carry bound skills' do
      let(:reviewer) { create(:ai_agent, account: account) }
      let(:tester) { create(:ai_agent, account: account) }
      let(:code_review) { create(:ai_skill, account: account, name: 'code_review') }
      let(:testing) { create(:ai_skill, account: account, name: 'Testing') }

      before do
        create(:ai_agent_team_member, team: team, agent: reviewer)
        create(:ai_agent_team_member, team: team, agent: tester)
        create(:ai_agent_skill, agent: reviewer, skill: code_review)
        create(:ai_agent_skill, agent: tester, skill: code_review)
        create(:ai_agent_skill, agent: tester, skill: testing)
      end

      it 'reports the skill names bound to the team agents' do
        coverage = service.analyze_composition(team)[:skill_coverage]

        expect(coverage[:skills]).to eq('code_review' => 2, 'testing' => 1)
        expect(coverage[:total_skills]).to eq(2)
        expect(coverage[:multi_covered_skills]).to eq(1)
        expect(coverage[:unique_skills]).to eq(1)
      end

      it 'reports a redundancy for the skill two agents share' do
        redundancies = service.analyze_composition(team)[:redundancies]

        expect(redundancies.map { |r| r[:skill] }).to eq(['code_review'])
        redundancy = redundancies.first
        expect(redundancy[:count]).to eq(2)
        expect(redundancy[:agents].map { |a| a[:name] }).to match_array([reviewer.name, tester.name])
        expect(redundancy[:agents].map { |a| a[:id] }).to match_array([reviewer.id, tester.id])
      end

      it 'clears the skill gaps the team actually covers' do
        expect(service.analyze_composition(team)[:gaps]).to be_empty
      end
    end

    context 'when a single agent covers the whole ideal skill breadth' do
      let(:agent) { create(:ai_agent, account: account) }

      before do
        create(:ai_agent_team_member, team: team, agent: agent)
        5.times { |i| create(:ai_agent_skill, agent: agent, skill: create(:ai_skill, account: account, name: "skill_#{i}")) }
      end

      it 'scores the team healthy instead of reporting no skills at all' do
        result = service.analyze_composition(team)

        expect(result[:coverage_score]).to eq(1.0)
        expect(result[:health]).to eq('healthy')
      end

      # With skill coverage always empty, skill_score was always 0 and
      # coverage_score could not exceed 0.4 — so no team ever reached "healthy"
      # and auto_optimize's early return was unreachable. Pin it now that a real
      # team can take it.
      it 'lets auto_optimize take its healthy early return' do
        expect(service.auto_optimize(team)).to eq(status: 'optimal', changes: [])
      end
    end

    # Negative control for the dead `respond_to?(:ai_agent_skills)` guards this
    # analysis used to carry, plus the positive twin that keeps the control from
    # passing vacuously: reflection works, the live association is `skills`, and
    # the join row is NOT a usable substitute because it has no #name.
    describe 'skill association reflection' do
      it 'exposes no :ai_agent_skills association on Ai::Agent' do
        expect(Ai::Agent.new).not_to respond_to(:ai_agent_skills)
      end

      # If Ai::AgentSkill ever gains a #name (a column, or `delegate :name, to:
      # :skill`), this example reds while production stays correct. That is the
      # intended prompt to revisit the traversal above — not a reason to delete
      # the example unread.
      it 'exposes :skills, whose elements carry #name while the join row does not' do
        expect(Ai::Agent.new).to respond_to(:skills)
        expect(Ai::Agent.new).to respond_to(:agent_skills)
        expect(Ai::Skill.new).to respond_to(:name)
        expect(Ai::AgentSkill.new).not_to respond_to(:name)
      end
    end
  end

  describe '#recommend_agents' do
    # Regression: `team.ai_agent_team_members` is not an association —
    # Ai::AgentTeam declares `has_many :members` (agent_team.rb:20). This
    # raised NoMethodError the first time TaskAnalyzerService reported ANY
    # capability gap, i.e. whenever the account has no agent at all matching
    # a requested capability — precisely the case this method exists to handle.
    it 'computes recommendations instead of raising on a capability gap' do
      result = nil
      expect {
        result = service.recommend_agents(team, 'Review the code for quality issues')
      }.not_to raise_error

      expect(result[:add]).to eq([])
      expect(result[:remove]).to eq([])
      expect(result[:current_coverage]).to eq(0.4)
      expect(result[:projected_coverage]).to eq(0.4)
    end
  end

  describe '#auto_optimize' do
    it 'returns optimal status for healthy teams' do
      allow(service).to receive(:analyze_composition).and_return({ health: 'healthy' })
      result = service.auto_optimize(team)
      expect(result[:status]).to eq('optimal')
      expect(result[:changes]).to eq([])
    end
  end
end
