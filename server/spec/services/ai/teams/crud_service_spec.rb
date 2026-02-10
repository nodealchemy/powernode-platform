# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Teams::CrudService, type: :service do
  let(:account) { create(:account) }

  subject(:service) { described_class.new(account: account) }

  describe '#list_teams' do
    let!(:team1) { create(:ai_agent_team, account: account, status: 'active') }
    let!(:team2) { create(:ai_agent_team, account: account, status: 'archived') }

    it 'returns all teams for the account' do
      result = service.list_teams
      expect(result.count).to eq(2)
    end

    it 'filters by status' do
      result = service.list_teams(status: 'active')
      expect(result.count).to eq(1)
      expect(result.first).to eq(team1)
    end
  end

  describe '#get_team' do
    let!(:team) { create(:ai_agent_team, account: account) }

    it 'returns the team by ID' do
      result = service.get_team(team.id)
      expect(result).to eq(team)
    end

    it 'raises RecordNotFound for invalid ID' do
      expect { service.get_team(SecureRandom.uuid) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#create_team' do
    it 'creates a team with valid params' do
      params = {
        name: 'Test Team',
        description: 'A test team',
        team_topology: 'hierarchical'
      }
      team = service.create_team(params)
      expect(team).to be_persisted
      expect(team.name).to eq('Test Team')
      expect(team.status).to eq('active')
      expect(team.team_type).to eq('hierarchical')
    end
  end

  describe '#update_team' do
    let!(:team) { create(:ai_agent_team, account: account, name: 'Old Name') }

    it 'updates allowed attributes' do
      result = service.update_team(team.id, { name: 'New Name' })
      expect(result.name).to eq('New Name')
    end
  end

  describe '#delete_team' do
    let!(:team) { create(:ai_agent_team, account: account) }

    it 'destroys the team' do
      service.delete_team(team.id)
      expect(Ai::AgentTeam.exists?(team.id)).to be false
    end
  end

  describe '#list_role_profiles' do
    it 'returns role profiles for the account' do
      result = service.list_role_profiles
      expect(result).to respond_to(:each)
    end
  end

  describe '#list_trajectories' do
    it 'delegates to TrajectoryService' do
      trajectory_service = instance_double(Ai::TrajectoryService)
      allow(Ai::TrajectoryService).to receive(:new).with(account: account).and_return(trajectory_service)
      allow(trajectory_service).to receive(:list_trajectories).with({}).and_return([])

      result = service.list_trajectories
      expect(result).to eq([])
    end
  end

  describe '#list_task_reviews' do
    it 'delegates to ReviewWorkflowService' do
      review_service = instance_double(Ai::ReviewWorkflowService)
      allow(Ai::ReviewWorkflowService).to receive(:new).with(account: account).and_return(review_service)
      allow(review_service).to receive(:list_reviews).with('task-id').and_return([])

      result = service.list_task_reviews('task-id')
      expect(result).to eq([])
    end
  end

  describe '#configure_team_review' do
    let!(:team) { create(:ai_agent_team, account: account) }

    it 'updates the team review config' do
      config = { 'auto_review_enabled' => true, 'review_mode' => 'blocking' }
      result = service.configure_team_review(team.id, config)
      expect(result.review_config).to eq(config)
    end
  end
end
