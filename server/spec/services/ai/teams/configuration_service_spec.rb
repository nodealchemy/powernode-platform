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

  describe '#analyze_composition' do
    it 'returns composition analysis for a team' do
      result = service.analyze_composition(team)
      expect(result).to include(:team_id, :team_name, :members_count, :skill_coverage, :role_balance, :coverage_score, :health)
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
