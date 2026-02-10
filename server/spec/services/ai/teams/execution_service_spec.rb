# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Teams::ExecutionService, type: :service do
  let(:account) { create(:account) }
  let(:team) { create(:ai_agent_team, account: account) }

  subject(:service) { described_class.new(account: account) }

  describe '#get_execution' do
    let!(:execution) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'pending', objective: 'Test') }

    it 'returns the execution by ID' do
      result = service.get_execution(execution.id)
      expect(result).to eq(execution)
    end

    it 'raises RecordNotFound for invalid ID' do
      expect { service.get_execution(SecureRandom.uuid) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#list_executions' do
    let!(:exec1) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'completed', objective: 'A', started_at: 2.hours.ago, completed_at: 1.hour.ago) }
    let!(:exec2) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'running', objective: 'B', started_at: 1.hour.ago) }

    it 'returns executions for a team' do
      result = service.list_executions(team.id)
      expect(result.count).to eq(2)
    end

    it 'filters by status' do
      result = service.list_executions(team.id, status: 'completed')
      expect(result.count).to eq(1)
      expect(result.first).to eq(exec1)
    end
  end

  describe '#create_task' do
    let!(:execution) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'running', objective: 'Test', started_at: Time.current) }

    it 'creates a task for the execution' do
      params = { description: 'Do something', task_type: 'execution' }
      task = service.create_task(execution.id, params)
      expect(task).to be_persisted
      expect(task.description).to eq('Do something')
      expect(task.task_type).to eq('execution')
    end
  end

  describe '#get_task' do
    let!(:execution) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'running', objective: 'Test', started_at: Time.current) }
    let!(:task) { Ai::TeamTask.create!(team_execution: execution, description: 'T1', status: 'pending', task_type: 'execution') }

    it 'returns the task by ID' do
      result = service.get_task(execution.id, task.id)
      expect(result).to eq(task)
    end
  end

  describe '#send_message' do
    let!(:role1) { Ai::TeamRole.create!(account: account, agent_team: team, role_name: 'lead', role_type: 'manager') }
    let!(:role2) { Ai::TeamRole.create!(account: account, agent_team: team, role_name: 'dev', role_type: 'worker') }
    let!(:execution) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'running', objective: 'Msg test', started_at: Time.current) }

    it 'raises RecordNotFound for invalid from_role_id' do
      expect {
        service.send_message(execution.id, { from_role_id: SecureRandom.uuid, content: 'Hi', message_type: 'task_update' })
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'creates message when both roles are valid' do
      msg = service.send_message(execution.id, {
        from_role_id: role1.id, to_role_id: role2.id,
        content: 'Do this', message_type: 'task_assignment'
      })
      expect(msg).to be_persisted
      expect(msg.from_role).to eq(role1)
      expect(msg.to_role).to eq(role2)
    end

    it 'works when roles are absent' do
      msg = service.send_message(execution.id, { content: 'Broadcast', message_type: 'broadcast' })
      expect(msg).to be_persisted
      expect(msg.from_role_id).to be_nil
      expect(msg.to_role_id).to be_nil
    end
  end
end
