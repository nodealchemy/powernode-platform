# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgentTeamMember, type: :model do
  # ==========================================
  # Associations
  # ==========================================
  describe 'associations' do
    it { should belong_to(:ai_agent_team) }
    it { should belong_to(:ai_agent) }
  end

  # ==========================================
  # Delegations
  # ==========================================
  describe 'delegations' do
    let(:team) { create(:ai_agent_team) }
    let(:agent) { create(:ai_agent, account: team.account, name: 'Test Agent') }
    let(:member) { create(:ai_agent_team_member, ai_agent_team: team, ai_agent: agent) }

    it 'delegates name to ai_agent' do
      expect(member.ai_agent_name).to eq('Test Agent')
    end

    it 'delegates account to ai_agent_team' do
      expect(member.account).to eq(team.account)
    end
  end

  # ==========================================
  # Validations
  # ==========================================
  describe 'validations' do
    subject { build(:ai_agent_team_member) }

    it { should validate_presence_of(:role) }
    it { should validate_numericality_of(:priority_order).is_greater_than_or_equal_to(0) }

    context 'uniqueness' do
      let(:team) { create(:ai_agent_team) }
      let(:agent) { create(:ai_agent, account: team.account) }
      let!(:existing_member) { create(:ai_agent_team_member, ai_agent_team: team, ai_agent: agent) }

      it 'prevents duplicate agent in same team' do
        duplicate = build(:ai_agent_team_member, ai_agent_team: team, ai_agent: agent)

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:ai_agent_id]).to include('already belongs to this team')
      end

      it 'allows same agent in different teams' do
        other_team = create(:ai_agent_team, account: team.account)
        member = build(:ai_agent_team_member, ai_agent_team: other_team, ai_agent: agent)

        expect(member).to be_valid
      end
    end

    describe 'single team lead validation' do
      let(:team) { create(:ai_agent_team) }
      let!(:existing_lead) { create(:ai_agent_team_member, :lead, ai_agent_team: team) }

      it 'prevents multiple leads in same team' do
        new_lead = build(:ai_agent_team_member, :lead, ai_agent_team: team)

        expect(new_lead).not_to be_valid
        expect(new_lead.errors[:is_lead]).to include('team can only have one lead')
      end

      it 'allows non-lead members when lead exists' do
        member = build(:ai_agent_team_member, ai_agent_team: team, is_lead: false)
        expect(member).to be_valid
      end
    end
  end

  # ==========================================
  # Scopes
  # ==========================================
  describe 'scopes' do
    let(:team) { create(:ai_agent_team) }
    let!(:lead_member) { create(:ai_agent_team_member, :lead, ai_agent_team: team, priority_order: 0) }
    let!(:researcher) { create(:ai_agent_team_member, :researcher, ai_agent_team: team, priority_order: 1) }
    let!(:writer) { create(:ai_agent_team_member, :writer, ai_agent_team: team, priority_order: 2) }

    it 'orders by priority' do
      expect(team.ai_agent_team_members.by_priority).to eq([ lead_member, researcher, writer ])
    end

    it 'filters by role' do
      expect(team.ai_agent_team_members.by_role('researcher')).to include(researcher)
      expect(team.ai_agent_team_members.by_role('researcher')).not_to include(lead_member, writer)
    end

    it 'filters leads' do
      expect(team.ai_agent_team_members.leads).to include(lead_member)
      expect(team.ai_agent_team_members.leads).not_to include(researcher, writer)
    end

    it 'filters non-leads' do
      expect(team.ai_agent_team_members.non_leads).to include(researcher, writer)
      expect(team.ai_agent_team_members.non_leads).not_to include(lead_member)
    end
  end

  # ==========================================
  # Callbacks
  # ==========================================
  describe 'callbacks' do
    it 'sets default values on create' do
      member = create(:ai_agent_team_member, capabilities: nil, member_config: nil)
      expect(member.capabilities).to eq([])
      expect(member.member_config).to eq({})
    end

    it 'auto-increments priority order' do
      team = create(:ai_agent_team)
      member1 = create(:ai_agent_team_member, ai_agent_team: team)
      member2 = create(:ai_agent_team_member, ai_agent_team: team)

      expect(member1.priority_order).to eq(0)
      expect(member2.priority_order).to eq(1)
    end

    it 'logs member registration on create' do
      expect(Rails.logger).to receive(:info).at_least(:once).with(/Member registered/)
      allow(Rails.logger).to receive(:info) # Allow other log messages
      create(:ai_agent_team_member)
    end

    it 'logs member removal on destroy' do
      member = create(:ai_agent_team_member)
      expect(Rails.logger).to receive(:info).with(/Member removed/)
      member.destroy
    end
  end

  # ==========================================
  # Instance Methods
  # ==========================================
  describe '#can_perform?' do
    let(:member) { create(:ai_agent_team_member, capabilities: [ 'research', 'analysis', 'writing' ]) }

    it 'returns true for included capabilities' do
      expect(member.can_perform?('research')).to be true
      expect(member.can_perform?(:analysis)).to be true
    end

    it 'returns false for non-included capabilities' do
      expect(member.can_perform?('coding')).to be false
    end
  end

  describe '#contribution_stats' do
    let(:member) { create(:ai_agent_team_member, :researcher) }

    it 'returns member contribution statistics' do
      stats = member.contribution_stats

      expect(stats[:role]).to eq('researcher')
      expect(stats).to include(:is_lead, :priority, :capabilities_count, :agent_name)
    end
  end

  describe '#promote_to_lead!' do
    let(:team) { create(:ai_agent_team) }
    let!(:existing_lead) { create(:ai_agent_team_member, :lead, ai_agent_team: team) }
    let(:member) { create(:ai_agent_team_member, ai_agent_team: team) }

    it 'promotes member to lead and demotes existing lead' do
      member.promote_to_lead!

      expect(member.reload.is_lead).to be true
      expect(existing_lead.reload.is_lead).to be false
    end
  end

  describe '#demote_from_lead!' do
    let(:lead_member) { create(:ai_agent_team_member, :lead) }

    it 'demotes member from lead' do
      lead_member.demote_from_lead!
      expect(lead_member.reload.is_lead).to be false
    end
  end

  describe '#set_priority' do
    let(:member) { create(:ai_agent_team_member, priority_order: 5) }

    it 'updates priority order' do
      member.set_priority(2)
      expect(member.reload.priority_order).to eq(2)
    end
  end

  # ==========================================
  # Factory Tests
  # ==========================================
  describe 'factories' do
    it 'has a valid default factory' do
      expect(build(:ai_agent_team_member)).to be_valid
    end

    it 'creates lead members' do
      member = create(:ai_agent_team_member, :lead)
      expect(member.is_lead).to be true
      expect(member.role).to eq('manager')
    end

    it 'creates researcher members' do
      member = create(:ai_agent_team_member, :researcher)
      expect(member.role).to eq('researcher')
      expect(member.capabilities).to include('research')
    end

    it 'creates writer members' do
      member = create(:ai_agent_team_member, :writer)
      expect(member.role).to eq('writer')
      expect(member.capabilities).to include('content_creation')
    end

    it 'creates reviewer members' do
      member = create(:ai_agent_team_member, :reviewer)
      expect(member.role).to eq('reviewer')
      expect(member.capabilities).to include('quality_assurance')
    end
  end
end
