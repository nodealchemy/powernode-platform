# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ContainerChatBridgeService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:template) { create(:devops_container_template, account: account) }
  let(:conversation) { create(:ai_conversation, account: account, user: user) }
  let(:deployment_service) { instance_double(Ai::ContainerAgentDeploymentService) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Ai::ContainerAgentDeploymentService).to receive(:new).and_return(deployment_service)
    allow(account).to receive(:container_instances).and_return(account.devops_container_instances)
  end

  describe '#route_message_to_container' do
    let(:message) { { content: 'Hello agent', role: 'user', metadata: {} } }

    context 'when an active container exists' do
      let!(:instance) do
        create(:devops_container_instance, :running,
               account: account,
               template: template,
               input_parameters: { 'conversation_id' => conversation.id.to_s })
      end

      it 'routes the message and returns success' do
        result = service.route_message_to_container(conversation_id: conversation.id, message: message)

        expect(result[:routed]).to be true
        expect(result[:container_execution_id]).to eq(instance.execution_id)
        expect(result[:container_status]).to eq('running')
      end

      it 'updates last_message_at on the instance' do
        freeze_time do
          service.route_message_to_container(conversation_id: conversation.id, message: message)
          instance.reload

          expect(instance.input_parameters['last_message_at']).to eq(Time.current.iso8601)
        end
      end

      it 'increments messages_routed counter' do
        service.route_message_to_container(conversation_id: conversation.id, message: message)
        instance.reload
        expect(instance.input_parameters['messages_routed']).to eq(1)

        service.route_message_to_container(conversation_id: conversation.id, message: message)
        instance.reload
        expect(instance.input_parameters['messages_routed']).to eq(2)
      end
    end

    context 'when no active container exists' do
      it 'returns routed false with reason' do
        result = service.route_message_to_container(conversation_id: conversation.id, message: message)

        expect(result[:routed]).to be false
        expect(result[:reason]).to eq('no_active_container')
      end
    end

    context 'when container is in completed status' do
      before do
        create(:devops_container_instance, :completed,
               account: account,
               template: template,
               input_parameters: { 'conversation_id' => conversation.id.to_s })
      end

      it 'does not route to completed containers' do
        result = service.route_message_to_container(conversation_id: conversation.id, message: message)

        expect(result[:routed]).to be false
        expect(result[:reason]).to eq('no_active_container')
      end
    end
  end

  describe '#handle_container_response' do
    let(:response_payload) do
      {
        content: 'Here is my analysis...',
        message_type: 'text',
        execution_id: 'exec-abc123',
        metadata: {
          tokens_used: 150,
          model: 'gpt-4',
          processing_time_ms: 2500
        }
      }
    end

    context 'when conversation exists (found by id)' do
      it 'creates an assistant message and returns success' do
        result = service.handle_container_response(
          conversation_id: conversation.id,
          response: response_payload
        )

        expect(result[:success]).to be true
        expect(result[:message_id]).to be_present
        expect(result[:conversation_id]).to eq(conversation.id)
      end
    end

    context 'when conversation is found by conversation_id field' do
      it 'creates an assistant message' do
        result = service.handle_container_response(
          conversation_id: conversation.conversation_id,
          response: response_payload
        )

        expect(result[:success]).to be true
        expect(result[:message_id]).to be_present
      end
    end

    context 'when conversation does not exist' do
      it 'returns failure with error message' do
        result = service.handle_container_response(
          conversation_id: SecureRandom.uuid,
          response: response_payload
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Conversation not found')
      end
    end

    context 'when response has missing optional metadata' do
      let(:minimal_response) { { content: 'Simple reply' } }

      it 'handles nil metadata gracefully' do
        result = service.handle_container_response(
          conversation_id: conversation.id,
          response: minimal_response
        )

        expect(result[:success]).to be true
      end
    end

    context 'when add_assistant_message raises an error' do
      before do
        allow_any_instance_of(Ai::Conversation).to receive(:add_assistant_message)
          .and_raise(StandardError, 'Database write failed')
      end

      it 'catches the error and returns failure' do
        result = service.handle_container_response(
          conversation_id: conversation.id,
          response: response_payload
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Database write failed')
      end
    end
  end

  describe '#ensure_container_for_conversation' do
    context 'when an active container already exists' do
      let!(:existing_instance) do
        create(:devops_container_instance, :running,
               account: account,
               template: template,
               input_parameters: { 'conversation_id' => conversation.id.to_s })
      end

      it 'returns the existing instance without deploying' do
        expect(deployment_service).not_to receive(:deploy_agent_session)

        result = service.ensure_container_for_conversation(
          conversation_id: conversation.id,
          agent: agent,
          user: user
        )

        expect(result).to eq(existing_instance)
      end
    end

    context 'when no active container exists' do
      let(:new_instance) { create(:devops_container_instance, :running, account: account, template: template) }

      it 'deploys a new container session' do
        expect(deployment_service).to receive(:deploy_agent_session)
          .with(agent: agent, conversation_id: conversation.id, user: user)
          .and_return(new_instance)

        result = service.ensure_container_for_conversation(
          conversation_id: conversation.id,
          agent: agent,
          user: user
        )

        expect(result).to eq(new_instance)
      end
    end

    context 'when user is nil' do
      it 'passes nil user to deployment service' do
        expect(deployment_service).to receive(:deploy_agent_session)
          .with(agent: agent, conversation_id: conversation.id, user: nil)
          .and_return(nil)

        service.ensure_container_for_conversation(
          conversation_id: conversation.id,
          agent: agent
        )
      end
    end

    context 'when deployment raises an error' do
      it 'returns nil' do
        allow(deployment_service).to receive(:deploy_agent_session)
          .and_raise(StandardError, 'Docker daemon unavailable')

        result = service.ensure_container_for_conversation(
          conversation_id: conversation.id,
          agent: agent,
          user: user
        )

        expect(result).to be_nil
      end
    end
  end

  describe '#container_enabled?' do
    it 'returns true when container_execution is enabled' do
      agent.mcp_metadata = { 'container_execution' => true }

      expect(service.container_enabled?(agent)).to be true
    end

    it 'returns false when container_execution is not set' do
      agent.mcp_metadata = {}

      expect(service.container_enabled?(agent)).to be false
    end

    it 'returns false when container_execution is false' do
      agent.mcp_metadata = { 'container_execution' => false }

      expect(service.container_enabled?(agent)).to be false
    end

    it 'returns false when mcp_metadata is nil' do
      agent.mcp_metadata = nil

      expect(service.container_enabled?(agent)).to be false
    end

    it 'returns false for string "true" value (must be boolean)' do
      agent.mcp_metadata = { 'container_execution' => 'true' }

      expect(service.container_enabled?(agent)).to be false
    end
  end

  describe '#has_active_container?' do
    context 'with an active container instance' do
      before do
        create(:devops_container_instance, :running,
               account: account,
               template: template,
               input_parameters: { 'conversation_id' => conversation.id.to_s })
      end

      it 'returns true' do
        expect(service.has_active_container?(conversation.id)).to be true
      end
    end

    context 'with a pending container instance' do
      before do
        create(:devops_container_instance, :pending,
               account: account,
               template: template,
               input_parameters: { 'conversation_id' => conversation.id.to_s })
      end

      it 'returns true (pending is considered active)' do
        expect(service.has_active_container?(conversation.id)).to be true
      end
    end

    context 'without any container instance' do
      it 'returns false' do
        expect(service.has_active_container?(conversation.id)).to be false
      end
    end

    context 'with only completed containers' do
      before do
        create(:devops_container_instance, :completed,
               account: account,
               template: template,
               input_parameters: { 'conversation_id' => conversation.id.to_s })
      end

      it 'returns false' do
        expect(service.has_active_container?(conversation.id)).to be false
      end
    end
  end

  describe '#terminate_conversation_container' do
    context 'when an active container exists' do
      let!(:instance) do
        create(:devops_container_instance, :running,
               account: account,
               template: template,
               input_parameters: { 'conversation_id' => conversation.id.to_s })
      end

      it 'terminates the container with a reason' do
        expect(deployment_service).to receive(:terminate_agent_session)
          .with(container_instance: instance, reason: 'User requested')

        service.terminate_conversation_container(
          conversation_id: conversation.id,
          reason: 'User requested'
        )
      end

      it 'uses default reason when none provided' do
        expect(deployment_service).to receive(:terminate_agent_session)
          .with(container_instance: instance, reason: 'Conversation ended')

        service.terminate_conversation_container(conversation_id: conversation.id)
      end
    end

    context 'when no active container exists' do
      it 'returns false without calling deployment service' do
        expect(deployment_service).not_to receive(:terminate_agent_session)

        result = service.terminate_conversation_container(conversation_id: conversation.id)
        expect(result).to be false
      end
    end
  end
end
