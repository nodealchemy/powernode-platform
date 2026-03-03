# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkspaceResponseJob, type: :job do
  subject(:job) { described_class.new }

  let(:conversation_id) { 'conv-123' }
  let(:message_id) { 'msg-456' }
  let(:agent_id) { 'agent-789' }
  let(:account_id) { 'account-101' }

  describe '#build_workspace_context' do
    let(:base_agent) { { 'name' => 'Test Agent', 'agent_type' => 'assistant' } }

    before do
      job.instance_variable_set(:@message_id, message_id)
      job.instance_variable_set(:@agent_id, agent_id)
    end

    context 'with mention segments in trigger message' do
      let(:trigger_message) do
        {
          'id' => message_id,
          'message_id' => message_id,
          'content' => "General context, @Agent check the deployment @Other do something",
          'content_metadata' => {
            'mention_segments' => {
              'preamble' => 'General context,',
              'segments' => {
                agent_id => 'check the deployment',
                'other-uuid' => 'do something'
              }
            }
          },
          'sender_info' => { 'name' => 'Rett' }
        }
      end

      let(:conversation_data) do
        {
          'title' => 'Workspace #2',
          'agent_team' => { 'name' => 'Workspace #2', 'members' => [] },
          'recent_messages' => [trigger_message]
        }
      end

      it 'includes targeted instruction in workspace context' do
        context = job.send(:build_workspace_context, conversation_data, base_agent)

        expect(context).to include('Your TARGETED instruction: "check the deployment"')
        expect(context).to include('General context from the user: "General context,"')
        expect(context).to include('Full message for reference:')
      end

      it 'does not include other agents segments' do
        context = job.send(:build_workspace_context, conversation_data, base_agent)

        expect(context).not_to include('"do something"')
      end
    end

    context 'without mention segments' do
      let(:trigger_message) do
        {
          'id' => message_id,
          'message_id' => message_id,
          'content' => 'Just a normal message',
          'content_metadata' => {},
          'sender_info' => { 'name' => 'Rett' }
        }
      end

      let(:conversation_data) do
        {
          'title' => 'Workspace #2',
          'agent_team' => { 'name' => 'Workspace #2', 'members' => [] },
          'recent_messages' => [trigger_message]
        }
      end

      it 'falls back gracefully with no targeted instruction' do
        context = job.send(:build_workspace_context, conversation_data, base_agent)

        expect(context).to include('You were @mentioned by Rett')
        expect(context).not_to include('TARGETED instruction')
      end
    end

    context 'with empty preamble' do
      let(:trigger_message) do
        {
          'id' => message_id,
          'message_id' => message_id,
          'content' => "@Agent check the deployment",
          'content_metadata' => {
            'mention_segments' => {
              'preamble' => '',
              'segments' => { agent_id => 'check the deployment' }
            }
          },
          'sender_info' => { 'name' => 'Rett' }
        }
      end

      let(:conversation_data) do
        {
          'title' => 'Workspace #2',
          'agent_team' => { 'name' => 'Workspace #2', 'members' => [] },
          'recent_messages' => [trigger_message]
        }
      end

      it 'includes targeted instruction but omits empty preamble' do
        context = job.send(:build_workspace_context, conversation_data, base_agent)

        expect(context).to include('Your TARGETED instruction: "check the deployment"')
        expect(context).not_to include('General context from the user')
      end
    end
  end
end
