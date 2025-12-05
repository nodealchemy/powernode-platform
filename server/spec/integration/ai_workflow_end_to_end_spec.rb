# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI Workflow End-to-End Integration', type: :integration do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:admin_user) { create(:user, :system_admin, account: account) }
  
  # AI Provider setup
  let!(:openai_provider) { create(:ai_provider, :openai, is_active: true) }
  let!(:openai_credential) do
    create(:ai_provider_credential,
           account: account,
           ai_provider: openai_provider,
           credentials: {
             api_key: 'sk-test1234567890abcdef',
             model: 'gpt-3.5-turbo'
           }.to_json,
           is_active: true,
           is_default: true)
  end

  # Workflow setup
  let!(:ai_workflow) do
    create(:ai_workflow,
           account: account,
           name: 'Customer Support Workflow',
           description: 'Automated customer support processing',
           is_active: true,
           input_schema: {
             type: 'object',
             properties: {
               customer_message: { type: 'string' },
               customer_id: { type: 'string' }
             },
             required: ['customer_message']
           })
  end

  # Workflow nodes
  let!(:start_node) do
    create(:ai_workflow_node,
           ai_workflow: ai_workflow,
           node_type: 'ai_agent',
           name: 'Classify Request',
           position: { x: 100, y: 100 },
           config: {
             model: 'gpt-3.5-turbo',
             temperature: 0.3,
             max_tokens: 100,
             instructions: 'Classify the customer request as: billing, technical, or general'
           })
  end

  let!(:condition_node) do
    create(:ai_workflow_node,
           ai_workflow: ai_workflow,
           node_type: 'condition',
           name: 'Route by Category',
           position: { x: 300, y: 100 },
           config: {
             conditions: [
               { field: 'classification', operator: 'equals', value: 'billing', output: 'billing_path' },
               { field: 'classification', operator: 'equals', value: 'technical', output: 'technical_path' },
               { field: 'classification', operator: 'default', value: true, output: 'general_path' }
             ]
           })
  end

  let!(:billing_node) do
    create(:ai_workflow_node,
           ai_workflow: ai_workflow,
           node_type: 'ai_agent',
           name: 'Billing Assistant',
           position: { x: 200, y: 300 },
           config: {
             model: 'gpt-3.5-turbo',
             temperature: 0.7,
             max_tokens: 200,
             instructions: 'Provide helpful billing support and generate a response'
           })
  end

  let!(:technical_node) do
    create(:ai_workflow_node,
           ai_workflow: ai_workflow,
           node_type: 'ai_agent',
           name: 'Technical Support',
           position: { x: 400, y: 300 },
           config: {
             model: 'gpt-4',
             temperature: 0.5,
             max_tokens: 300,
             instructions: 'Provide technical support and troubleshooting assistance'
           })
  end

  let!(:output_node) do
    create(:ai_workflow_node,
           ai_workflow: ai_workflow,
           node_type: 'output',
           name: 'Final Response',
           position: { x: 300, y: 500 },
           config: {
             output_format: 'json',
             fields: ['response', 'category', 'confidence']
           })
  end

  # Workflow edges
  let!(:edge1) do
    create(:ai_workflow_edge,
           ai_workflow: ai_workflow,
           source_node: start_node,
           target_node: condition_node)
  end

  let!(:edge2) do
    create(:ai_workflow_edge,
           ai_workflow: ai_workflow,
           source_node: condition_node,
           target_node: billing_node,
           condition: 'billing_path')
  end

  let!(:edge3) do
    create(:ai_workflow_edge,
           ai_workflow: ai_workflow,
           source_node: condition_node,
           target_node: technical_node,
           condition: 'technical_path')
  end

  let!(:edge4) do
    create(:ai_workflow_edge,
           ai_workflow: ai_workflow,
           source_node: billing_node,
           target_node: output_node)
  end

  let!(:edge5) do
    create(:ai_workflow_edge,
           ai_workflow: ai_workflow,
           source_node: technical_node,
           target_node: output_node)
  end

  before do
    # Mock AI provider responses
    stub_openai_requests
    
    # Enable WebSocket testing
    ActionCable.server.config.cable = { adapter: 'test' }
    
    # Setup authentication
    sign_in user
  end

  describe 'Complete Workflow Execution Lifecycle' do
    context 'with billing support request' do
      let(:input_data) do
        {
          customer_message: 'I have been charged twice for my subscription this month',
          customer_id: 'cust_12345'
        }
      end

      it 'executes complete workflow from start to finish' do
        # Step 1: Create workflow execution via API
        post '/api/v1/workflow_executions', params: {
          execution: {
            ai_workflow_id: ai_workflow.id,
            input_data: input_data,
            execution_options: {
              async: false,
              priority: 'normal'
            }
          }
        }

        expect(response).to have_http_status(:ok)
        execution_response = JSON.parse(response.body)
        execution_id = execution_response['data']['execution_id']

        # Step 2: Verify execution was created
        execution = AiWorkflowExecution.find(execution_id)
        expect(execution.status).to eq('pending')
        expect(execution.input_data).to eq(input_data.stringify_keys)

        # Step 3: Process the execution (normally done by background job)
        perform_workflow_execution(execution)

        # Step 4: Verify workflow completed successfully
        execution.reload
        expect(execution.status).to eq('completed')
        expect(execution.output_data).to be_present
        expect(execution.output_data['category']).to eq('billing')
        expect(execution.output_data['response']).to include('billing')

        # Step 5: Verify all node executions
        node_executions = execution.ai_workflow_node_executions.order(:created_at)
        expect(node_executions.count).to eq(4) # start -> condition -> billing -> output

        # Classification node executed
        classify_execution = node_executions.find { |ne| ne.ai_workflow_node_id == start_node.id }
        expect(classify_execution.status).to eq('completed')
        expect(classify_execution.output_data['classification']).to eq('billing')

        # Condition node executed
        condition_execution = node_executions.find { |ne| ne.ai_workflow_node_id == condition_node.id }
        expect(condition_execution.status).to eq('completed')
        expect(condition_execution.output_data['selected_path']).to eq('billing_path')

        # Billing node executed (not technical)
        billing_execution = node_executions.find { |ne| ne.ai_workflow_node_id == billing_node.id }
        expect(billing_execution).to be_present
        expect(billing_execution.status).to eq('completed')

        technical_execution = node_executions.find { |ne| ne.ai_workflow_node_id == technical_node.id }
        expect(technical_execution).to be_nil # Should not execute

        # Output node executed
        output_execution = node_executions.find { |ne| ne.ai_workflow_node_id == output_node.id }
        expect(output_execution.status).to eq('completed')

        # Step 6: Verify execution logs were created
        logs = execution.ai_workflow_execution_logs.order(:created_at)
        expect(logs.count).to be >= 4
        expect(logs.map(&:message)).to include(
          match(/Workflow execution started/),
          match(/Node.*executed successfully/),
          match(/Workflow execution completed/)
        )

        # Step 7: Verify audit trail
        audit_logs = AuditLog.where(
          auditable_type: 'AiWorkflowExecution',
          auditable_id: execution_id
        ).order(:created_at)
        
        expect(audit_logs.count).to be >= 2
        expect(audit_logs.map(&:action)).to include(
          'ai_workflow_execution_created',
          'ai_workflow_execution_completed'
        )

        # Step 8: Verify metrics were tracked
        expect(execution.metadata).to include(
          'total_tokens_used',
          'total_cost',
          'execution_duration_ms',
          'nodes_executed'
        )
        expect(execution.metadata['total_tokens_used']).to be > 0
        expect(execution.metadata['total_cost']).to be > 0
      end

      it 'handles real-time WebSocket updates during execution' do
        # Subscribe to execution channel
        cable = ActionCable.server.config.cable[:adapter]
        connection = ActionCable::TestCase::TestConnection.new
        channel = AiAgentExecutionChannel.new(connection, {})

        # Create and execute workflow
        post '/api/v1/workflow_executions', params: {
          execution: {
            ai_workflow_id: ai_workflow.id,
            input_data: input_data,
            execution_options: { async: true }
          }
        }

        execution_id = JSON.parse(response.body)['data']['execution_id']

        # Simulate real-time updates during execution
        updates_received = []
        
        allow(ActionCable.server).to receive(:broadcast) do |channel_name, data|
          if channel_name == "ai_agent_execution_#{execution_id}"
            updates_received << data
          end
        end

        # Process execution and verify updates
        execution = AiWorkflowExecution.find(execution_id)
        perform_workflow_execution(execution)

        # Verify we received progress updates
        expect(updates_received).to include(
          hash_including('type' => 'status_update', 'status' => 'running'),
          hash_including('type' => 'progress_update'),
          hash_including('type' => 'execution_completed')
        )
      end
    end

    context 'with technical support request' do
      let(:input_data) do
        {
          customer_message: 'My API requests are returning 500 errors',
          customer_id: 'cust_67890'
        }
      end

      it 'routes to technical support path' do
        post '/api/v1/workflow_executions', params: {
          execution: {
            ai_workflow_id: ai_workflow.id,
            input_data: input_data
          }
        }

        execution_id = JSON.parse(response.body)['data']['execution_id']
        execution = AiWorkflowExecution.find(execution_id)
        
        perform_workflow_execution(execution)

        execution.reload
        expect(execution.status).to eq('completed')
        expect(execution.output_data['category']).to eq('technical')

        # Verify technical node was executed, not billing
        node_executions = execution.ai_workflow_node_executions
        technical_execution = node_executions.find { |ne| ne.ai_workflow_node_id == technical_node.id }
        billing_execution = node_executions.find { |ne| ne.ai_workflow_node_id == billing_node.id }

        expect(technical_execution).to be_present
        expect(technical_execution.status).to eq('completed')
        expect(billing_execution).to be_nil
      end
    end

    context 'with error handling and recovery' do
      it 'handles AI provider failures gracefully' do
        # Mock provider failure
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_return(status: 500, body: 'Internal Server Error')

        post '/api/v1/workflow_executions', params: {
          execution: {
            ai_workflow_id: ai_workflow.id,
            input_data: { customer_message: 'test message' }
          }
        }

        execution_id = JSON.parse(response.body)['data']['execution_id']
        execution = AiWorkflowExecution.find(execution_id)

        perform_workflow_execution(execution)

        execution.reload
        expect(execution.status).to eq('failed')
        expect(execution.error_message).to include('provider')

        # Verify error was logged
        error_logs = execution.ai_workflow_execution_logs.where(level: 'error')
        expect(error_logs.count).to be >= 1
        expect(error_logs.first.message).to include('error')
      end

      it 'supports workflow execution retry' do
        # First execution fails
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_return(status: 500, body: 'Internal Server Error')

        post '/api/v1/workflow_executions', params: {
          execution: {
            ai_workflow_id: ai_workflow.id,
            input_data: { customer_message: 'test message' }
          }
        }

        execution_id = JSON.parse(response.body)['data']['execution_id']
        original_execution = AiWorkflowExecution.find(execution_id)
        perform_workflow_execution(original_execution)

        expect(original_execution.reload.status).to eq('failed')

        # Retry the execution
        stub_openai_requests # Now provider works

        post "/api/v1/workflow_executions/#{execution_id}/retry"
        expect(response).to have_http_status(:ok)

        retry_response = JSON.parse(response.body)
        retry_execution_id = retry_response['data']['execution_id']
        retry_execution = AiWorkflowExecution.find(retry_execution_id)

        perform_workflow_execution(retry_execution)

        expect(retry_execution.reload.status).to eq('completed')
        expect(retry_execution.original_execution_id).to eq(execution_id)
      end

      it 'handles workflow cancellation' do
        # Start long-running execution
        post '/api/v1/workflow_executions', params: {
          execution: {
            ai_workflow_id: ai_workflow.id,
            input_data: { customer_message: 'test message' },
            execution_options: { async: true }
          }
        }

        execution_id = JSON.parse(response.body)['data']['execution_id']
        execution = AiWorkflowExecution.find(execution_id)
        execution.update!(status: 'running')

        # Cancel the execution
        post "/api/v1/workflow_executions/#{execution_id}/cancel", params: {
          reason: 'User requested cancellation'
        }

        expect(response).to have_http_status(:ok)
        
        # Verify cancellation was processed
        expect(AiExecutionCancellationJob).to have_been_enqueued
          .with(hash_including(
            execution_id: execution_id,
            cancellation_reason: 'User requested cancellation'
          ))
      end
    end

    context 'with complex workflow validation' do
      it 'validates workflow connectivity before execution' do
        # Create invalid workflow (missing edges)
        broken_workflow = create(:ai_workflow, account: account)
        isolated_node = create(:ai_workflow_node, ai_workflow: broken_workflow)

        post '/api/v1/workflow_executions', params: {
          execution: {
            ai_workflow_id: broken_workflow.id,
            input_data: { test: 'data' }
          }
        }

        expect(response).to have_http_status(:unprocessable_content)
        error_response = JSON.parse(response.body)
        expect(error_response['error']).to include('validation')
      end

      it 'validates input data against workflow schema' do
        post '/api/v1/workflow_executions', params: {
          execution: {
            ai_workflow_id: ai_workflow.id,
            input_data: { invalid_field: 'test' } # Missing required customer_message
          }
        }

        expect(response).to have_http_status(:unprocessable_content)
        error_response = JSON.parse(response.body)
        expect(error_response['error']).to include('customer_message')
      end
    end

    context 'with performance monitoring' do
      it 'tracks execution performance metrics' do
        post '/api/v1/workflow_executions', params: {
          execution: {
            ai_workflow_id: ai_workflow.id,
            input_data: { customer_message: 'performance test' }
          }
        }

        execution_id = JSON.parse(response.body)['data']['execution_id']
        execution = AiWorkflowExecution.find(execution_id)

        start_time = Time.current
        perform_workflow_execution(execution)
        end_time = Time.current

        execution.reload
        
        # Verify performance metrics
        expect(execution.metadata['execution_duration_ms']).to be_within(1000).of((end_time - start_time) * 1000)
        expect(execution.metadata['nodes_executed']).to eq(4)
        expect(execution.metadata['avg_node_duration_ms']).to be > 0

        # Verify metrics were stored for analytics
        get "/api/v1/workflow_executions/#{execution_id}/analytics"
        expect(response).to have_http_status(:ok)
        
        analytics = JSON.parse(response.body)['data']['analytics']
        expect(analytics).to include(
          'execution_time',
          'token_usage',
          'cost_breakdown',
          'performance_score'
        )
      end
    end

    context 'with multi-user collaboration' do
      let(:collaborator) { create(:user, account: account) }

      it 'supports multiple users monitoring same execution' do
        # User 1 starts execution
        sign_in user
        post '/api/v1/workflow_executions', params: {
          execution: {
            ai_workflow_id: ai_workflow.id,
            input_data: { customer_message: 'collaboration test' }
          }
        }

        execution_id = JSON.parse(response.body)['data']['execution_id']

        # User 2 can view execution
        sign_in collaborator
        get "/api/v1/workflow_executions/#{execution_id}"
        expect(response).to have_http_status(:ok)

        execution_data = JSON.parse(response.body)['data']['execution']
        expect(execution_data['id']).to eq(execution_id)

        # Both users can see execution logs
        get "/api/v1/workflow_executions/#{execution_id}/logs"
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'Cross-Component Integration' do
    it 'integrates conversation with workflow execution' do
      # Create AI conversation
      conversation = create(:ai_conversation,
                          account: account,
                          user: user,
                          ai_provider: openai_provider)

      # Send message that triggers workflow
      post "/api/v1/conversations/#{conversation.id}/messages", params: {
        message: {
          content: 'I need help with my billing',
          metadata: {
            trigger_workflow: ai_workflow.id
          }
        }
      }

      expect(response).to have_http_status(:ok)
      message_response = JSON.parse(response.body)
      
      # Verify workflow was triggered
      expect(AiWorkflowExecution.where(
        ai_workflow_id: ai_workflow.id,
        account_id: account.id
      ).count).to eq(1)

      execution = AiWorkflowExecution.last
      expect(execution.metadata['triggered_by']).to eq('conversation')
      expect(execution.metadata['conversation_id']).to eq(conversation.id)
    end

    it 'integrates provider health monitoring with execution' do
      # Simulate unhealthy provider
      openai_credential.update!(
        health_status: 'unhealthy',
        last_failure_at: 1.minute.ago,
        failure_count: 3
      )

      post '/api/v1/workflow_executions', params: {
        execution: {
          ai_workflow_id: ai_workflow.id,
          input_data: { customer_message: 'test with unhealthy provider' }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      error_response = JSON.parse(response.body)
      expect(error_response['error']).to include('provider')
      expect(error_response['error']).to include('unhealthy')
    end

    it 'integrates with background job processing' do
      # Enable async processing
      post '/api/v1/workflow_executions', params: {
        execution: {
          ai_workflow_id: ai_workflow.id,
          input_data: { customer_message: 'async test' },
          execution_options: { async: true }
        }
      }

      expect(response).to have_http_status(:accepted)
      
      # Verify background job was enqueued
      expect(AiConversationProcessingJob).to have_been_enqueued
      
      # Process jobs and verify completion
      perform_enqueued_jobs do
        # Jobs should complete successfully
      end

      execution = AiWorkflowExecution.last
      expect(execution.status).to eq('completed')
    end
  end

  private

  def perform_workflow_execution(execution)
    # Simulate the orchestration service executing the workflow
    orchestration_service = AiAgentOrchestrationService.new(execution)
    orchestration_service.execute_workflow
  end

  def stub_openai_requests
    # Classification response
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with(body: hash_including(
        messages: array_including(
          hash_including(content: /Classify the customer request/)
        )
      ))
      .to_return(
        status: 200,
        body: {
          choices: [
            {
              message: {
                role: 'assistant',
                content: 'billing'
              }
            }
          ],
          usage: { total_tokens: 25 }
        }.to_json
      )

    # Billing support response
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with(body: hash_including(
        messages: array_including(
          hash_including(content: /billing support/)
        )
      ))
      .to_return(
        status: 200,
        body: {
          choices: [
            {
              message: {
                role: 'assistant',
                content: 'I understand you have a billing concern. Let me help you with that double charge issue.'
              }
            }
          ],
          usage: { total_tokens: 45 }
        }.to_json
      )

    # Technical support response
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with(body: hash_including(
        messages: array_including(
          hash_including(content: /technical support/)
        )
      ))
      .to_return(
        status: 200,
        body: {
          choices: [
            {
              message: {
                role: 'assistant',
                content: 'I can help you troubleshoot those 500 errors. Let me guide you through some diagnostic steps.'
              }
            }
          ],
          usage: { total_tokens: 55 }
        }.to_json
      )
  end
end