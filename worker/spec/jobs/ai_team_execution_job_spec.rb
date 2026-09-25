# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTeamExecutionJob do
  let(:job) { described_class.new }
  let(:strategy_path) { '/api/v1/internal/ai/teams/t-1/execute_strategy' }

  before do
    mock_powernode_worker_config
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow(job).to receive(:ai_suspended?).and_return(false)
  end

  it 'runs the strategy on the execution the caller created, without creating another' do
    expect(job).not_to receive(:create_execution)
    expect(job).to receive(:backend_api_post)
      .with(strategy_path, hash_including(execution_id: 'exec-1'))
      .and_return('success' => true, 'data' => {})

    job.execute('team_id' => 't-1', 'user_id' => 'u-1', 'account_id' => 'a-1', 'execution_id' => 'exec-1')
  end

  it 'creates the execution itself when none is passed' do
    expect(job).to receive(:create_execution).and_return('id' => 'exec-2')
    expect(job).to receive(:backend_api_post)
      .with(strategy_path, hash_including(execution_id: 'exec-2'))
      .and_return('success' => true, 'data' => {})

    job.execute('team_id' => 't-1', 'user_id' => 'u-1', 'account_id' => 'a-1')
  end
end
