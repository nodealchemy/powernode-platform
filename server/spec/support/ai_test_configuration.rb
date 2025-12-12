# frozen_string_literal: true

# AI Testing Configuration and Setup
RSpec.configure do |config|
  # AI-specific test configuration
  config.before(:suite) do
    # Clear any cached AI providers or configurations
    Rails.cache.clear if Rails.cache.respond_to?(:clear)

    # Set up test environment for AI components
    ENV['AI_TEST_MODE'] = 'true'
    ENV['SKIP_AI_PROVIDER_VALIDATION'] = 'true' unless ENV['REAL_AI_TESTING']
  end

  config.after(:suite) do
    # Cleanup after AI test suite
    ENV.delete('AI_TEST_MODE')
    ENV.delete('SKIP_AI_PROVIDER_VALIDATION')
  end

  # Before each test with AI components
  config.before(:each, :ai_test) do
    # Mock AI provider responses by default
    mock_ai_provider_responses unless ENV['REAL_AI_TESTING']

    # Set up common test data
    @test_account = create(:account)
    @test_user = create(:user, account: @test_account)

    # Mock current user and account for controllers
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(@test_user)
    allow_any_instance_of(ApplicationController).to receive(:current_account).and_return(@test_account)
    allow_any_instance_of(ApplicationController).to receive(:authenticate_request).and_return(true)
  end

  config.after(:each, :ai_test) do
    # Clean up test data
    clean_up_ai_test_data
  end

  # Performance testing configuration
  config.before(:each, :performance) do
    @performance_threshold = {
      response_time: 2.0, # seconds
      memory_increase: 50, # MB
      database_queries: 20
    }

    @initial_memory = get_memory_usage
    @query_count = 0

    # Track database queries
    ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      @query_count += 1 unless args.last[:sql].include?('SCHEMA')
    end
  end

  config.after(:each, :performance) do
    final_memory = get_memory_usage
    memory_increase = final_memory - @initial_memory

    # Check performance thresholds
    if memory_increase > @performance_threshold[:memory_increase]
      puts "Warning: Test used #{memory_increase}MB memory (threshold: #{@performance_threshold[:memory_increase]}MB)"
    end

    if @query_count > @performance_threshold[:database_queries]
      puts "Warning: Test executed #{@query_count} queries (threshold: #{@performance_threshold[:database_queries]})"
    end
  end

  # Security testing configuration
  config.before(:each, :security) do
    # Enable strict security validations
    @original_sanitize_settings = ActionController::Base.sanitized_allowed_tags.dup
    @original_strip_settings = ActionController::Base.sanitized_allowed_attributes.dup

    # More restrictive sanitization for security tests
    ActionController::Base.sanitized_allowed_tags.clear
    ActionController::Base.sanitized_allowed_attributes.clear

    # Mock security services
    allow(AiCredentialEncryptionService).to receive(:encrypt_credentials)
      .and_return('encrypted_test_data')
    allow(AiCredentialEncryptionService).to receive(:decrypt_credentials)
      .and_return('{"api_key": "***masked***"}')
  end

  config.after(:each, :security) do
    # Restore original sanitization settings
    ActionController::Base.sanitized_allowed_tags.replace(@original_sanitize_settings)
    ActionController::Base.sanitized_allowed_attributes.replace(@original_strip_settings)
  end

  # Integration testing configuration
  config.before(:each, :integration) do
    # Use real database transactions for integration tests
    DatabaseCleaner.strategy = :truncation

    # Set up comprehensive test data
    setup_integration_test_data

    # Enable all audit logging
    allow(AuditLog).to receive(:create!).and_call_original
  end

  config.after(:each, :integration) do
    # Restore normal database cleaning
    DatabaseCleaner.strategy = :transaction

    # Cleanup integration test data
    cleanup_integration_test_data
  end

  # Analytics testing configuration
  config.before(:each, :analytics) do
    # Mock time to ensure consistent analytics calculations
    @stubbed_time = Time.parse('2025-01-15 12:00:00 UTC')
    allow(Time).to receive(:current).and_return(@stubbed_time)
    allow(Date).to receive(:current).and_return(@stubbed_time.to_date)

    # Create analytics test data
    create_analytics_baseline_data
  end

  config.after(:each, :analytics) do
    # Cleanup analytics test data
    cleanup_analytics_data
  end

  private

  def mock_ai_provider_responses
    # Mock successful AI provider responses
    success_response = {
      'content' => 'This is a mocked AI response for testing.',
      'metadata' => {
        'tokens_used' => 150,
        'response_time_ms' => 1200,
        'model_used' => 'test-model-v1',
        'confidence_score' => 0.95
      }
    }

    allow_any_instance_of(AiProviderClientService).to receive(:execute_request)
      .and_return(success_response)

    # Mock provider testing service
    allow_any_instance_of(AiProviderTestService).to receive(:test_with_details)
      .and_return({ success: true, response_time_ms: 800 })

    # Mock cost calculation
    allow_any_instance_of(AiCostOptimizationService).to receive(:calculate_execution_cost)
      .and_return(0.05)
  end

  def clean_up_ai_test_data
    # Clean up any test data that might persist between tests
    if defined?(@test_account)
      AiAgentExecution.where(account: @test_account).delete_all
      AiMessage.where(account: @test_account).delete_all
      AiConversation.where(account: @test_account).delete_all
      AiAgent.where(account: @test_account).delete_all
      AiProviderCredential.where(account: @test_account).delete_all
    end
  end

  def get_memory_usage
    # Simple memory usage tracking (in MB)
    if RUBY_PLATFORM.include?('linux')
      `ps -o pid,rss -p #{Process.pid}`.split("\n").last.split.last.to_i / 1024.0
    else
      0 # Fallback for non-Linux systems
    end
  end

  def setup_integration_test_data
    # Create comprehensive test data for integration tests
    @integration_account = create(:account, name: 'Integration Test Account')
    @integration_user = create(:user, account: @integration_account)

    # Create providers with credentials
    @integration_providers = [
      create(:ai_provider, slug: 'openai', name: 'OpenAI'),
      create(:ai_provider, slug: 'anthropic', name: 'Anthropic'),
      create(:ai_provider, slug: 'ollama', name: 'Ollama')
    ]

    @integration_credentials = @integration_providers.map do |provider|
      create(:ai_provider_credential,
        account: @integration_account,
        ai_provider: provider,
        name: "#{provider.name} Credential")
    end

    # Create agents
    @integration_agents = @integration_providers.map do |provider|
      create(:ai_agent,
        account: @integration_account,
        ai_provider: provider,
        name: "#{provider.name} Agent")
    end
  end

  def cleanup_integration_test_data
    # Cleanup integration test data
    if defined?(@integration_account)
      @integration_account.destroy
    end
  end

  def create_analytics_baseline_data
    return unless defined?(@test_account)

    # Create 30 days of historical data
    30.times do |days_ago|
      date = days_ago.days.ago(@stubbed_time)

      # Create some executions for each day
      rand(3..8).times do
        create(:ai_agent_execution, :completed,
          account: @test_account,
          created_at: date,
          metadata: {
            cost: rand(0.01..0.10),
            response_time_ms: rand(800..2000),
            tokens_used: rand(100..500)
          })
      end

      # Add some failures
      if rand < 0.1 # 10% chance of failures
        create(:ai_agent_execution, :failed,
          account: @test_account,
          created_at: date)
      end
    end
  end

  def cleanup_analytics_data
    # Analytics cleanup is handled by regular test cleanup
  end
end

# Custom test metadata for AI components
module AiTestMetadata
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def describe_ai_component(component_name, &block)
      describe(component_name, :ai_test, &block)
    end

    def describe_ai_controller(controller_name, &block)
      describe(controller_name, :ai_test, type: :request, &block)
    end

    def describe_ai_service(service_name, &block)
      describe(service_name, :ai_test, &block)
    end

    def describe_ai_job(job_name, &block)
      describe(job_name, :ai_test, type: :job, &block)
    end

    def describe_ai_channel(channel_name, &block)
      describe(channel_name, :ai_test, type: :channel, &block)
    end

    def describe_performance(description, &block)
      describe(description, :performance, &block)
    end

    def describe_security(description, &block)
      describe(description, :security, &block)
    end

    def describe_integration(description, &block)
      describe(description, :integration, &block)
    end

    def describe_analytics(description, &block)
      describe(description, :analytics, &block)
    end
  end
end

# Include AI test metadata methods
RSpec.configure do |config|
  config.include AiTestMetadata
  config.extend AiTestMetadata::ClassMethods
end

# AI Test Data Generators
class AiTestDataGenerator
  class << self
    def generate_conversation_history(conversation, days_back: 7, messages_per_day: 5)
      messages = []

      (0..days_back).each do |days_ago|
        date = days_ago.days.ago

        messages_per_day.times do |i|
          messages << {
            ai_conversation: conversation,
            account: conversation.account,
            sender_type: i.even? ? 'user' : 'ai',
            sender_id: i.even? ? conversation.account.users.first&.id : nil,
            content: "Test message #{i + 1} from #{days_ago} days ago",
            created_at: date + i.hours
          }
        end
      end

      AiMessage.create!(messages)
    end

    def generate_execution_history(agent, days_back: 30, executions_per_day: 3)
      executions = []

      (0..days_back).each do |days_ago|
        date = days_ago.days.ago

        executions_per_day.times do |i|
          status = rand < 0.9 ? 'completed' : 'failed' # 90% success rate

          executions << {
            ai_agent: agent,
            account: agent.account,
            status: status,
            input_data: { prompt: "Test execution #{i + 1}" },
            output_data: status == 'completed' ? { result: 'Test result' } : nil,
            metadata: {
              cost: rand(0.01..0.15),
              response_time_ms: rand(500..3000),
              tokens_used: rand(50..800)
            },
            created_at: date + i.hours,
            completed_at: status == 'completed' ? date + i.hours + 30.seconds : nil
          }
        end
      end

      AiAgentExecution.create!(executions)
    end

    def generate_workflow_test_data(account)
      workflow = create(:ai_workflow, account: account, name: 'Generated Test Workflow')

      # Create a simple 3-node workflow
      nodes = []
      3.times do |i|
        nodes << create(:ai_workflow_node,
          ai_workflow: workflow,
          node_type: [ 'ai_agent', 'condition', 'ai_agent' ][i],
          name: "Node #{i + 1}",
          position_x: 100 + (i * 200),
          position_y: 200)
      end

      # Connect the nodes
      2.times do |i|
        create(:ai_workflow_edge,
          ai_workflow: workflow,
          source_node: nodes[i],
          target_node: nodes[i + 1],
          condition_type: 'always')
      end

      workflow
    end
  end
end
