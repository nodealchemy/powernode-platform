# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowNodeExecutionJob, type: :job do
  let(:account_id) { SecureRandom.uuid }
  let(:user_id) { SecureRandom.uuid }
  let(:workflow_id) { SecureRandom.uuid }
  let(:workflow_run_id) { SecureRandom.uuid }
  let(:node_execution_id) { SecureRandom.uuid }
  let(:node_id) { SecureRandom.uuid }
  let(:agent_id) { SecureRandom.uuid }

  let(:node_execution_data) do
    {
      'id' => node_execution_id,
      'ai_workflow_run_id' => workflow_run_id,
      'node_id' => node_id,
      'node_type' => 'ai_agent',
      'status' => 'pending',
      'input_data' => {
        'prompt' => 'Analyze the provided data and generate insights',
        'temperature' => 0.7,
        'max_tokens' => 2000
      },
      'configuration' => {
        'agent_id' => agent_id,
        'model' => 'gpt-4',
        'temperature' => 0.7,
        'max_tokens' => 2000,
        'system_prompt' => 'You are an AI data analyst.'
      },
      'started_at' => Time.current.iso8601,
      'execution_context' => {
        'workflow_run_id' => workflow_run_id,
        'account_id' => account_id,
        'user_id' => user_id
      }
    }
  end

  let(:successful_execution_response) do
    {
      'success' => true,
      'data' => {
        'output_data' => {
          'content' => 'Based on the analysis, I found the following key patterns...',
          'confidence_score' => 0.95,
          'key_insights' => ['Pattern A', 'Pattern B', 'Anomaly detected'],
          'metadata' => {
            'analysis_type' => 'comprehensive',
            'data_quality' => 'high'
          }
        },
        'cost' => 0.25,
        'tokens_consumed' => 150,
        'tokens_generated' => 300,
        'duration_ms' => 5000,
        'provider' => 'OpenAI'
      }
    }
  end

  let(:failed_execution_response) do
    {
      'success' => false,
      'error' => 'Node execution failed: API timeout',
      'data' => {
        'error_details' => {
          'error_type' => 'timeout',
          'timeout_seconds' => 30,
          'provider' => 'OpenAI'
        }
      }
    }
  end

  let(:execution_context) do
    {
      'node_id' => node_id,
      'node_type' => 'ai_agent',
      'input_data' => node_execution_data['input_data'],
      'configuration' => node_execution_data['configuration'],
      'workflow_context' => {
        'workflow_id' => workflow_id,
        'account_id' => account_id,
        'user_id' => user_id
      },
      'started_at' => Time.current.iso8601
    }
  end

  let(:job) { described_class.new }

  before do
    mock_powernode_worker_config
    # Bypass runaway loop detection in tests (it uses Redis)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  describe '#execute' do
    context 'when node execution succeeds' do
      before do
        # Use WebMock stubs - note: job uses hyphenated paths (workflow-node-executions)
        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", {
          'success' => true,
          'data' => { 'node_execution' => node_execution_data }
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/execute", successful_execution_response)

        stub_backend_api_success(:patch, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", { 'success' => true })

        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/next-nodes", {
          'success' => true,
          'data' => { 'next_nodes' => [] }
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflow-runs/#{workflow_run_id}/broadcast", { 'success' => true })

        # Stub workflow runs endpoint for error propagation handling
        stub_backend_api_success(:get, "/api/v1/ai/workflow-runs/#{workflow_run_id}", {
          'success' => true,
          'data' => {
            'workflow_run' => {
              'id' => workflow_run_id,
              'status' => 'running'
            }
          }
        })
        stub_backend_api_success(:post, "/api/v1/ai/workflow-runs/#{workflow_run_id}/cancel", { 'success' => true })
        stub_backend_api_success(:post, "/api/v1/ai/workflow-runs/#{workflow_run_id}/retry", { 'success' => true })
      end

      it 'fetches node execution data from backend' do
        job.execute(node_execution_id, execution_context)

        expect_api_request(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}")
      end

      it 'executes node via backend API' do
        job.execute(node_execution_id, execution_context)

        expect_api_request(:post, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/execute")
      end

      it 'updates node execution status to completed' do
        job.execute(node_execution_id, execution_context)

        expect(WebMock).to have_requested(:patch, /workflow-node-executions\/#{node_execution_id}/)
          .with(body: hash_including({
            'node_execution' => hash_including('status' => 'completed')
          }))
      end

      it 'checks for next nodes to execute' do
        job.execute(node_execution_id, execution_context)

        expect(WebMock).to have_requested(:get, /workflow-node-executions\/#{node_execution_id}\/next-nodes/)
      end

      it 'logs successful completion' do
        logger_double = mock_logger

        job.execute(node_execution_id, execution_context)

        expect(logger_double).to have_received(:info).with(
          a_string_matching(/Starting node execution/)
        )
        expect(logger_double).to have_received(:info).with(
          a_string_matching(/completed successfully/)
        )
      end

      it 'includes execution metrics in completion update' do
        job.execute(node_execution_id, execution_context)

        expect(WebMock).to have_requested(:patch, /workflow-node-executions\/#{node_execution_id}/)
          .with(body: hash_including({
            'node_execution' => hash_including('cost' => kind_of(Numeric))
          }))
      end
    end

    context 'when node execution fails' do
      before do
        # Use hyphenated paths to match job implementation
        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", {
          'success' => true,
          'data' => { 'node_execution' => node_execution_data }
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/execute", failed_execution_response)

        stub_backend_api_success(:patch, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", { 'success' => true })

        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/next-nodes", {
          'success' => true,
          'data' => { 'next_nodes' => [] }
        })

        # Stub workflow error propagation endpoints
        stub_backend_api_success(:get, "/api/v1/ai/workflow-runs/#{workflow_run_id}", {
          'success' => true,
          'data' => {
            'workflow_run' => {
              'id' => workflow_run_id,
              'ai_workflow' => { 'configuration' => { 'error_handling' => 'stop' } }
            }
          }
        })
        stub_backend_api_success(:post, "/api/v1/ai/workflow-runs/#{workflow_run_id}/cancel", { 'success' => true })
      end

      it 'updates node execution status to failed' do
        job.execute(node_execution_id, execution_context)

        expect(WebMock).to have_requested(:patch, /workflow-node-executions\/#{node_execution_id}/)
          .with(body: hash_including({
            'node_execution' => hash_including('status' => 'failed')
          }))
      end

      it 'handles workflow error propagation' do
        job.execute(node_execution_id, execution_context)

        expect(WebMock).to have_requested(:post, /workflow-runs\/#{workflow_run_id}\/cancel/)
      end

      it 'logs error details' do
        logger_double = mock_logger

        job.execute(node_execution_id, execution_context)

        expect(logger_double).to have_received(:error).with(
          a_string_matching(/Node execution failed/i)
        )
      end
    end

    context 'when node execution data is not found' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", {
          'success' => false,
          'error' => 'Node execution not found'
        })
      end

      it 'logs error and returns early' do
        logger_double = mock_logger

        job.execute(node_execution_id, execution_context)

        expect(logger_double).to have_received(:error).with(
          a_string_matching(/Failed to fetch node execution.*Node execution not found/)
        )

        # Should not attempt execution
        expect(WebMock).not_to have_requested(:post, /workflow-node-executions\/#{node_execution_id}\/execute/)
      end
    end

    context 'when job encounters an exception' do
      let(:test_error) { StandardError.new('Unexpected node execution error') }

      before do
        # Stub get to return valid data, but make post raise an error
        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", {
          'success' => true,
          'data' => { 'node_execution' => node_execution_data }
        })

        # Make the execute endpoint raise an exception
        stub_request(:post, /workflow-node-executions\/#{node_execution_id}\/execute/)
          .to_raise(test_error)

        stub_backend_api_success(:patch, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", { 'success' => true })

        # Stub workflow error propagation endpoints
        stub_backend_api_success(:get, "/api/v1/ai/workflow-runs/#{workflow_run_id}", {
          'success' => true,
          'data' => {
            'workflow_run' => {
              'id' => workflow_run_id,
              'ai_workflow' => { 'configuration' => { 'error_handling' => 'stop' } }
            }
          }
        })
        stub_backend_api_success(:post, "/api/v1/ai/workflow-runs/#{workflow_run_id}/cancel", { 'success' => true })
      end

      it 'handles exceptions gracefully' do
        expect { job.execute(node_execution_id, execution_context) }.to raise_error(test_error)
      end

      it 'updates node execution status to failed on exception' do
        expect { job.execute(node_execution_id, execution_context) }.to raise_error(test_error)

        expect(WebMock).to have_requested(:patch, /workflow-node-executions\/#{node_execution_id}/)
          .with(body: hash_including({
            'node_execution' => hash_including('status' => 'failed')
          }))
      end

      it 'broadcasts error status on exception' do
        expect { job.execute(node_execution_id, execution_context) }.to raise_error(test_error)

        expect(WebMock).to have_requested(:post, /workflow-runs\/#{workflow_run_id}\/cancel/)
      end
    end
  end

  describe 'different node types' do
    let(:api_call_node_data) do
      node_execution_data.merge(
        'node_type' => 'api_call',
        'configuration' => {
          'url' => 'https://api.example.com/process',
          'method' => 'POST',
          'headers' => { 'Content-Type' => 'application/json' },
          'timeout' => 30
        }
      )
    end

    let(:webhook_node_data) do
      node_execution_data.merge(
        'node_type' => 'webhook',
        'configuration' => {
          'url' => 'https://webhook.example.com/notify',
          'method' => 'POST',
          'payload_template' => '{"status": "{{status}}", "data": "{{data}}"}'
        }
      )
    end

    let(:condition_node_data) do
      node_execution_data.merge(
        'node_type' => 'condition',
        'configuration' => {
          'condition' => 'input.score > 0.8',
          'true_path' => 'success_node',
          'false_path' => 'failure_node'
        }
      )
    end

    context 'when executing API call node' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", {
          'success' => true,
          'data' => { 'node_execution' => api_call_node_data }
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/execute", {
          'success' => true,
          'data' => {
            'output_data' => {
              'response' => { 'result' => 'success', 'data' => 'processed' },
              'status_code' => 200,
              'headers' => { 'content-type' => 'application/json' }
            },
            'cost' => 0.01,
            'duration_ms' => 2000
          }
        })

        stub_backend_api_success(:patch, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", { 'success' => true })
        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/next-nodes", {
          'success' => true,
          'data' => { 'next_nodes' => [] }
        })
      end

      it 'executes API call node correctly' do
        job.execute(node_execution_id, execution_context)

        expect(WebMock).to have_requested(:patch, /workflow-node-executions\/#{node_execution_id}/)
          .with(body: hash_including({
            'node_execution' => hash_including('status' => 'completed')
          }))
      end
    end

    context 'when executing webhook node' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", {
          'success' => true,
          'data' => { 'node_execution' => webhook_node_data }
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/execute", {
          'success' => true,
          'data' => {
            'output_data' => {
              'webhook_delivered' => true,
              'url' => 'https://webhook.example.com/notify',
              'response_code' => 200,
              'delivery_time' => Time.current.iso8601
            },
            'cost' => 0.005,
            'duration_ms' => 1500
          }
        })

        stub_backend_api_success(:patch, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", { 'success' => true })
        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/next-nodes", {
          'success' => true,
          'data' => { 'next_nodes' => [] }
        })
      end

      it 'executes webhook node correctly' do
        job.execute(node_execution_id, execution_context)

        expect(WebMock).to have_requested(:patch, /workflow-node-executions\/#{node_execution_id}/)
          .with(body: hash_including({
            'node_execution' => hash_including('status' => 'completed')
          }))
      end
    end

    context 'when executing condition node' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", {
          'success' => true,
          'data' => { 'node_execution' => condition_node_data }
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/execute", {
          'success' => true,
          'data' => {
            'output_data' => {
              'condition_result' => true,
              'condition' => 'input.score > 0.8',
              'next_path' => 'success_node',
              'evaluation_details' => {
                'input_score' => 0.95,
                'threshold' => 0.8
              }
            },
            'cost' => 0.001,
            'duration_ms' => 100
          }
        })

        stub_backend_api_success(:patch, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", { 'success' => true })
        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/next-nodes", {
          'success' => true,
          'data' => { 'next_nodes' => [] }
        })
      end

      it 'executes condition node correctly' do
        job.execute(node_execution_id, execution_context)

        expect(WebMock).to have_requested(:patch, /workflow-node-executions\/#{node_execution_id}/)
          .with(body: hash_including({
            'node_execution' => hash_including('status' => 'completed')
          }))
      end
    end
  end

  describe 'retry and timeout handling' do
    context 'when node execution times out' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", {
          'success' => true,
          'data' => { 'node_execution' => node_execution_data }
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/execute", {
          'success' => false,
          'error' => 'Execution timeout after 30 seconds',
          'data' => {
            'error_details' => {
              'error_type' => 'timeout',
              'timeout_seconds' => 30
            }
          }
        })

        stub_backend_api_success(:patch, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", { 'success' => true })

        # Stub workflow error propagation endpoints
        stub_backend_api_success(:get, "/api/v1/ai/workflow-runs/#{workflow_run_id}", {
          'success' => true,
          'data' => {
            'workflow_run' => {
              'id' => workflow_run_id,
              'ai_workflow' => { 'configuration' => { 'error_handling' => 'stop' } }
            }
          }
        })
        stub_backend_api_success(:post, "/api/v1/ai/workflow-runs/#{workflow_run_id}/cancel", { 'success' => true })
      end

      it 'handles timeout gracefully' do
        job.execute(node_execution_id, execution_context)

        expect(WebMock).to have_requested(:patch, /workflow-node-executions\/#{node_execution_id}/)
          .with(body: hash_including({
            'node_execution' => hash_including('status' => 'failed')
          }))
      end
    end

    context 'with retry configuration' do
      before do
        # Simulate node with retry configuration
        node_with_retry = node_execution_data.merge(
          'configuration' => node_execution_data['configuration'].merge(
            'max_retries' => 3,
            'retry_delay' => 1
          )
        )

        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", {
          'success' => true,
          'data' => { 'node_execution' => node_with_retry }
        })

        stub_backend_api_success(:post, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/execute", successful_execution_response)
        stub_backend_api_success(:patch, "/api/v1/ai/workflow-node-executions/#{node_execution_id}", { 'success' => true })
        stub_backend_api_success(:get, "/api/v1/ai/workflow-node-executions/#{node_execution_id}/next-nodes", {
          'success' => true,
          'data' => { 'next_nodes' => [] }
        })
      end

      it 'includes retry configuration in execution context' do
        job.execute(node_execution_id, execution_context)

        expect(WebMock).to have_requested(:post, /workflow-node-executions\/#{node_execution_id}\/execute/)
      end
    end
  end

  describe 'sidekiq configuration' do
    it 'is configured for ai_workflow_nodes queue' do
      expect(described_class.sidekiq_options_hash['queue']).to eq('ai_workflow_nodes')
    end

    it 'has retry configuration' do
      expect(described_class.sidekiq_options_hash['retry']).to eq(5)
    end

    it 'includes AiJobsConcern' do
      expect(described_class.included_modules).to include(AiJobsConcern)
    end
  end
end