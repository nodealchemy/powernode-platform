# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Agent executions record their source', type: :model do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account, status: 'active') }

  it 'stamps execution_context["source"] = "platform" on a row Agent#execute creates' do
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute)
      .and_return('result' => { 'output' => 'ok', 'metadata' => {} })

    execution = agent.execute({ 'input' => 'hi' }, user: agent.creator)

    expect(execution.execution_context['source']).to eq('platform')
  end
end
