# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AgentTeam, type: :model do
  # ==========================================
  # Associations
  # ==========================================
  describe 'associations' do
    it { should belong_to(:account) }
    it { should have_many(:members).dependent(:destroy) }
    it { should have_many(:agents).through(:members) }
    it { should have_many(:ai_team_roles).dependent(:destroy) }
    it { should have_many(:ai_team_channels).dependent(:destroy) }
    it { should have_many(:team_executions).dependent(:destroy) }
    it { should have_many(:compound_learnings).dependent(:nullify) }
  end

  # ==========================================
  # Validations
  # ==========================================
  describe 'validations' do
    subject { build(:ai_agent_team) }

    it { should validate_presence_of(:name) }
    it { should validate_inclusion_of(:team_type).in_array(Ai::AgentTeam::TEAM_TYPES) }
    it { should validate_inclusion_of(:coordination_strategy).in_array(Ai::AgentTeam::COORDINATION_STRATEGIES) }
    it { should validate_inclusion_of(:status).in_array(Ai::AgentTeam::STATUSES) }

    context 'uniqueness' do
      let!(:existing_team) { create(:ai_agent_team) }

      it 'validates uniqueness of name scoped to account' do
        duplicate = build(:ai_agent_team,
                         name: existing_team.name,
                         account: existing_team.account)

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include('has already been taken')
      end

      it 'allows same name in different accounts' do
        other_account = create(:account)
        same_name_team = build(:ai_agent_team,
                               name: existing_team.name,
                               account: other_account)

        expect(same_name_team).to be_valid
      end
    end

    describe 'coordination compatibility' do
      it 'warns when hierarchical team uses consensus coordination' do
        team = build(:ai_agent_team, team_type: 'hierarchical', coordination_strategy: 'consensus')
        expect(team).not_to be_valid
        expect(team.errors[:coordination_strategy]).to be_present
      end

      it 'warns when mesh team uses manager_led coordination' do
        team = build(:ai_agent_team, team_type: 'mesh', coordination_strategy: 'manager_led')
        expect(team).not_to be_valid
        expect(team.errors[:coordination_strategy]).to be_present
      end

      it 'allows hierarchical team with manager_led coordination' do
        team = build(:ai_agent_team, team_type: 'hierarchical', coordination_strategy: 'manager_led')
        expect(team).to be_valid
      end

      it 'allows mesh team with consensus coordination' do
        team = build(:ai_agent_team, team_type: 'mesh', coordination_strategy: 'consensus')
        expect(team).to be_valid
      end
    end
  end

  # ==========================================
  # Scopes
  # ==========================================
  describe 'scopes' do
    let!(:active_team) { create(:ai_agent_team, status: 'active') }
    let!(:inactive_team) { create(:ai_agent_team, status: 'inactive') }
    let!(:archived_team) { create(:ai_agent_team, status: 'archived') }
    let!(:hierarchical_team) { create(:ai_agent_team, team_type: 'hierarchical') }
    let!(:mesh_team) { create(:ai_agent_team, :mesh) }

    it 'filters active teams' do
      expect(Ai::AgentTeam.active).to include(active_team, hierarchical_team, mesh_team)
      expect(Ai::AgentTeam.active).not_to include(inactive_team, archived_team)
    end

    it 'filters inactive teams' do
      expect(Ai::AgentTeam.inactive).to include(inactive_team)
    end

    it 'filters archived teams' do
      expect(Ai::AgentTeam.archived).to include(archived_team)
    end

    it 'filters by team type' do
      expect(Ai::AgentTeam.hierarchical).to include(hierarchical_team, active_team)
      expect(Ai::AgentTeam.mesh).to include(mesh_team)
    end
  end

  # ==========================================
  # Callbacks
  # ==========================================
  describe 'callbacks' do
    it 'sets default values on create' do
      team = create(:ai_agent_team, team_config: nil, status: nil)
      expect(team.team_config).to eq({})
      expect(team.status).to eq('active')
    end

    it 'logs team creation' do
      expect(Rails.logger).to receive(:info).with(/Team created/)
      create(:ai_agent_team)
    end
  end

  # ==========================================
  # Instance Methods
  # ==========================================
  describe '#team_lead' do
    it 'returns the team lead member' do
      team = create(:ai_agent_team, :with_lead)
      expect(team.team_lead).to be_present
      expect(team.team_lead.is_lead).to be true
    end

    it 'returns nil when no lead exists' do
      team = create(:ai_agent_team)
      expect(team.team_lead).to be_nil
    end
  end

  describe '#has_lead?' do
    it 'returns true when team has a lead' do
      team = create(:ai_agent_team, :with_lead)
      expect(team.has_lead?).to be true
    end

    it 'returns false when team has no lead' do
      team = create(:ai_agent_team)
      expect(team.has_lead?).to be false
    end
  end

  describe '#ordered_members' do
    it 'returns members ordered by priority' do
      team = create(:ai_agent_team)
      # Create members - auto-increment will assign priorities 0, 1, 2
      member1 = create(:ai_agent_team_member, team: team)
      member2 = create(:ai_agent_team_member, team: team)
      member3 = create(:ai_agent_team_member, team: team)

      # Verify they're ordered by priority
      ordered = team.ordered_members
      expect(ordered.map(&:id)).to eq([ member1.id, member2.id, member3.id ])
      expect(ordered.map(&:priority_order)).to eq([ 0, 1, 2 ])
    end
  end

  describe '#team_stats' do
    it 'returns team statistics' do
      team = create(:ai_agent_team, :with_members, members_count: 5)
      stats = team.team_stats

      expect(stats[:member_count]).to eq(5)
      expect(stats[:team_type]).to eq('hierarchical')
      expect(stats[:status]).to eq('active')
    end
  end

  describe '#archive!' do
    it 'archives the team' do
      team = create(:ai_agent_team, status: 'active')
      team.archive!
      expect(team.status).to eq('archived')
    end
  end

  describe '#activate!' do
    it 'activates the team' do
      team = create(:ai_agent_team, status: 'inactive')
      team.activate!
      expect(team.status).to eq('active')
    end
  end

  describe '#deactivate!' do
    it 'deactivates the team' do
      team = create(:ai_agent_team, status: 'active')
      team.deactivate!
      expect(team.status).to eq('inactive')
    end
  end

  describe '#add_member' do
    it 'adds a member to the team' do
      team = create(:ai_agent_team)
      agent = create(:ai_agent, account: team.account)

      member = team.add_member(
        agent: agent,
        role: 'researcher',
        capabilities: [ 'research', 'analysis' ]
      )

      expect(member).to be_persisted
      expect(member.role).to eq('researcher')
      expect(member.capabilities).to eq([ 'research', 'analysis' ])
    end

    it 'sets priority order automatically' do
      team = create(:ai_agent_team)
      agent1 = create(:ai_agent, account: team.account)
      agent2 = create(:ai_agent, account: team.account)

      member1 = team.add_member(agent: agent1, role: 'writer')
      member2 = team.add_member(agent: agent2, role: 'reviewer')

      expect(member1.priority_order).to eq(0)
      expect(member2.priority_order).to eq(1)
    end
  end

  describe '#remove_member' do
    it 'removes a member from the team' do
      team = create(:ai_agent_team, :with_members, members_count: 3)
      agent = team.agents.first

      expect {
        team.remove_member(agent)
      }.to change { team.members.count }.by(-1)
    end
  end

  # ==========================================
  # Factory Tests
  # ==========================================
  describe 'factories' do
    it 'has a valid default factory' do
      expect(build(:ai_agent_team)).to be_valid
    end

    it 'creates hierarchical teams' do
      team = create(:ai_agent_team, :hierarchical)
      expect(team.team_type).to eq('hierarchical')
      expect(team.coordination_strategy).to eq('manager_led')
    end

    it 'creates mesh teams' do
      team = create(:ai_agent_team, :mesh)
      expect(team.team_type).to eq('mesh')
      expect(team.coordination_strategy).to eq('consensus')
    end

    it 'creates content generation crew' do
      team = create(:ai_agent_team, :content_generation_crew)
      expect(team.members.count).to eq(3)
      expect(team.has_lead?).to be true
      expect(team.members.pluck(:role)).to match_array([ 'researcher', 'writer', 'reviewer' ])
    end
  end
end
