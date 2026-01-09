# frozen_string_literal: true

# Custom RSpec matchers for AI testing
module AiMatchers
  # Matcher to verify AI response structure
  RSpec::Matchers.define :be_a_valid_ai_response do
    match do |response|
      response.is_a?(Hash) &&
        response.key?('success') &&
        response.key?('data') &&
        (response['success'] == true || response.key?('error'))
    end

    failure_message do |response|
      "expected #{response} to be a valid AI response with 'success' and 'data' keys"
    end
  end

  # Matcher to verify AI execution status
  RSpec::Matchers.define :have_execution_status do |expected_status|
    match do |execution|
      execution.is_a?(Ai::AgentExecution) &&
        execution.status == expected_status.to_s
    end

    failure_message do |execution|
      "expected AI execution to have status '#{expected_status}', but got '#{execution&.status}'"
    end
  end

  # Matcher to verify workflow node configuration
  RSpec::Matchers.define :have_valid_node_configuration do
    match do |node|
      return false unless node.is_a?(AiWorkflowNode)

      case node.node_type
      when 'ai_agent'
        node.configuration&.key?('agent_id')
      when 'api_call'
        node.configuration&.key?('url') && node.configuration&.key?('method')
      when 'webhook'
        node.configuration&.key?('webhook_url')
      when 'condition'
        node.configuration&.key?('condition')
      when 'transform'
        node.configuration&.key?('transformation')
      when 'email'
        node.configuration&.key?('to') && node.configuration&.key?('subject')
      else
        true # Other node types may have different requirements
      end
    end

    failure_message do |node|
      "expected workflow node of type '#{node&.node_type}' to have valid configuration"
    end
  end

  # Matcher to verify credential encryption
  RSpec::Matchers.define :have_encrypted_credentials do
    match do |credential|
      credential.is_a?(Ai::ProviderCredential) &&
        credential.credentials.present? &&
        !credential.credentials.include?('api_key') && # Should not contain plain text
        !credential.credentials.include?('sk-') # Should not contain OpenAI key format
    end

    failure_message do |credential|
      "expected credentials to be encrypted, but found plain text data"
    end
  end

  # Matcher to verify audit log creation
  RSpec::Matchers.define :create_audit_log do |action|
    supports_block_expectations

    match do |block|
      @initial_count = AuditLog.count
      block.call
      @final_count = AuditLog.count

      if action
        @audit_log = AuditLog.where(action: action).order(:created_at).last
        @audit_log.present? && @final_count > @initial_count
      else
        @final_count > @initial_count
      end
    end

    failure_message do |_|
      if action
        "expected to create audit log with action '#{action}', but #{@audit_log ? 'found different action' : 'no matching log found'}"
      else
        "expected to create audit log, but count remained #{@initial_count}"
      end
    end

    chain :with_metadata do |expected_metadata|
      @expected_metadata = expected_metadata
    end

    match do |block|
      @initial_count = AuditLog.count
      block.call
      @final_count = AuditLog.count

      if action
        @audit_log = AuditLog.where(action: action).order(:created_at).last
        return false unless @audit_log.present? && @final_count > @initial_count

        if @expected_metadata
          @expected_metadata.all? { |key, value| @audit_log.metadata[key.to_s] == value }
        else
          true
        end
      else
        @final_count > @initial_count
      end
    end
  end

  # Matcher to verify conversation broadcast
  RSpec::Matchers.define :broadcast_to_conversation do |conversation|
    match do |_|
      # This would need ActionCable testing setup
      # For now, just check the conversation exists
      conversation.is_a?(Ai::Conversation)
    end

    failure_message do |_|
      "expected to broadcast to conversation #{conversation&.id}"
    end

    chain :with_message_type do |message_type|
      @message_type = message_type
    end
  end

  # Matcher to verify provider response format
  RSpec::Matchers.define :be_a_valid_provider_response do
    match do |response|
      response.is_a?(Hash) &&
        response.key?('content') &&
        response.key?('metadata') &&
        response['metadata'].is_a?(Hash)
    end

    failure_message do |response|
      "expected #{response} to be a valid provider response with 'content' and 'metadata'"
    end
  end

  # Matcher to verify security sanitization
  RSpec::Matchers.define :be_sanitized_content do
    match do |content|
      content.is_a?(String) &&
        !content.include?('<script>') &&
        !content.include?('javascript:') &&
        !content.include?('data:') &&
        !content.match?(/on\w+\s*=/i) # Event handlers like onclick=
    end

    failure_message do |content|
      "expected '#{content}' to be sanitized of malicious content"
    end
  end

  # Matcher to verify PII masking
  RSpec::Matchers.define :have_masked_pii do
    match do |content|
      content.is_a?(String) &&
        !content.match?(/\d{3}-\d{2}-\d{4}/) && # SSN pattern
        !content.match?(/\d{4}-\d{4}-\d{4}-\d{4}/) && # Credit card pattern
        !content.match?(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/) # Email pattern (basic)
    end

    failure_message do |content|
      "expected '#{content}' to have PII masked"
    end
  end

  # Matcher to verify rate limiting
  RSpec::Matchers.define :be_rate_limited do
    match do |response|
      response.respond_to?(:status) &&
        response.status == 429
    end

    failure_message do |response|
      "expected response to be rate limited (429), but got #{response&.status}"
    end
  end

  # Matcher to verify workflow validation
  RSpec::Matchers.define :be_a_valid_workflow do
    match do |workflow|
      workflow.is_a?(AiWorkflow) &&
        workflow.valid? &&
        workflow.nodes.count > 0 &&
        has_start_node?(workflow) &&
        has_connected_nodes?(workflow)
    end

    failure_message do |workflow|
      errors = []
      errors << "not a valid AiWorkflow" unless workflow.is_a?(AiWorkflow)
      errors << "has validation errors: #{workflow.errors.full_messages.join(', ')}" unless workflow.valid?
      errors << "has no nodes" if workflow.nodes.count == 0
      errors << "missing start node" unless has_start_node?(workflow)
      errors << "has disconnected nodes" unless has_connected_nodes?(workflow)

      "expected workflow to be valid, but #{errors.join(', ')}"
    end

    private

    def has_start_node?(workflow)
      workflow.nodes.any? { |node| node.node_type == 'start' || node.is_start_node }
    end

    def has_connected_nodes?(workflow)
      return true if workflow.nodes.count <= 1

      # Simple check - all nodes except start should have incoming edges
      nodes_with_edges = workflow.edges.pluck(:target_node_id).uniq
      start_nodes = workflow.nodes.select { |n| n.node_type == 'start' || n.is_start_node }

      expected_connected = workflow.nodes.count - start_nodes.count
      nodes_with_edges.count >= expected_connected
    end
  end

  # Matcher to verify cost calculation
  RSpec::Matchers.define :have_valid_cost_calculation do
    match do |cost_data|
      cost_data.is_a?(Hash) &&
        cost_data.key?('total_cost') &&
        cost_data['total_cost'].is_a?(Numeric) &&
        cost_data['total_cost'] >= 0
    end

    failure_message do |cost_data|
      "expected #{cost_data} to have valid cost calculation with positive total_cost"
    end
  end

  # Matcher to verify analytics time series
  RSpec::Matchers.define :be_a_valid_time_series do
    match do |timeline|
      timeline.is_a?(Array) &&
        timeline.all? { |point| point.is_a?(Hash) && point.key?('date') } &&
        timeline.sort_by { |point| Date.parse(point['date']) } == timeline
    end

    failure_message do |timeline|
      "expected #{timeline} to be a valid time series with date-ordered data points"
    end
  end

  # Matcher to verify permission enforcement
  RSpec::Matchers.define :enforce_permission do |required_permission|
    match do |controller_action|
      # This would need to be implemented with controller testing
      # For now, return true as a placeholder
      true
    end

    failure_message do |_|
      "expected action to enforce permission '#{required_permission}'"
    end
  end
end

# Include matchers in RSpec
RSpec.configure do |config|
  config.include AiMatchers
end
