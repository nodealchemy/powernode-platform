# frozen_string_literal: true

class Ai::DebuggingService
  module ReplayAndProfiling
    extend ActiveSupport::Concern

    private

    def extract_original_input(execution)
      execution.input_parameters || {}
    end

    def reconstruct_execution_steps(execution)
      steps = []
      steps << { step: 1, action: "created", timestamp: execution.created_at&.iso8601, details: "Input: #{execution.input_parameters&.keys&.join(', ')}" }
      steps << { step: 2, action: "started", timestamp: execution.started_at&.iso8601, details: "Provider: #{execution.provider&.name}" } if execution.started_at
      if execution.child_executions.any?
        execution.child_executions.order(:created_at).each_with_index do |child, idx|
          steps << { step: steps.size + 1, action: "child_execution", timestamp: child.created_at&.iso8601, details: "Agent: #{child.agent&.name}, Status: #{child.status}" }
        end
      end
      steps << { step: steps.size + 1, action: execution.status, timestamp: execution.completed_at&.iso8601, details: execution.error_message } if execution.completed_at
      steps
    end

    def extract_provider_interactions(execution)
      interactions = [{
        interaction: "primary_call",
        provider: execution.provider&.name,
        model: execution.performance_metrics&.dig("model"),
        tokens_used: execution.tokens_used,
        cost_usd: execution.cost_usd,
        duration_ms: execution.duration_ms,
        timestamp: execution.started_at&.iso8601
      }]
      execution.child_executions.order(:created_at).each do |child|
        interactions << {
          interaction: "child_call",
          provider: child.provider&.name,
          tokens_used: child.tokens_used,
          cost_usd: child.cost_usd,
          duration_ms: child.duration_ms,
          timestamp: child.started_at&.iso8601
        }
      end
      interactions
    end

    def extract_state_changes(execution)
      changes = [{ from: nil, to: "pending", timestamp: execution.created_at&.iso8601 }]
      changes << { from: "pending", to: "running", timestamp: execution.started_at&.iso8601 } if execution.started_at
      changes << { from: "running", to: execution.status, timestamp: execution.completed_at&.iso8601 } if execution.completed_at
      changes
    end

    def identify_error_points(execution)
      return [] unless execution.error_message
      [ { error: execution.error_message, timestamp: execution.completed_at&.iso8601 } ]
    end

    def generate_replay_instructions(execution)
      instructions = []
      instructions << "1. Ensure provider '#{execution.provider&.name}' is active and credentials are valid"
      instructions << "2. Input parameters: #{execution.input_parameters&.to_json&.truncate(200)}"
      if execution.error_message.present?
        instructions << "3. Previous error: #{execution.error_message}"
        instructions << "4. Check if the error condition has been resolved before retrying"
      end
      instructions << "#{instructions.size + 1}. Retry via: AgentExecution.create!(agent: Agent.find('#{execution.ai_agent_id}'), input_parameters: <original_input>)"
      instructions
    end

    def store_execution_replay(execution_id, replay_data)
      key = "execution_replay:#{@account.id}:#{execution_id}"
      @redis.setex(key, 7.days, replay_data.to_json)
    end

    def build_execution_timeline(execution)
      timeline = []
      timeline << { event: "created", timestamp: execution.created_at.iso8601 }
      timeline << { event: "started", timestamp: execution.started_at.iso8601 } if execution.started_at
      timeline << { event: "completed", timestamp: execution.completed_at.iso8601 } if execution.completed_at
      timeline
    end

    def identify_performance_bottlenecks(execution)
      bottlenecks = []
      if execution.duration_ms && execution.duration_ms > 10000
        bottlenecks << "Execution time exceeds 10 seconds"
      end
      bottlenecks
    end

    def analyze_resource_usage(execution)
      {
        tokens_used: execution.tokens_used,
        cost_usd: execution.cost_usd,
        duration_ms: execution.duration_ms,
        child_executions: execution.child_executions.count,
        total_tokens_with_children: execution.total_tokens_with_children,
        total_cost_with_children: execution.total_cost_with_children
      }
    end

    def analyze_network_performance(execution)
      {
        total_latency_ms: execution.duration_ms,
        provider: execution.provider&.name,
        provider_type: execution.provider&.provider_type,
        estimated_network_overhead_ms: execution.duration_ms.to_i > 0 ? [execution.duration_ms.to_i * 0.1, 50].max.round(0) : nil
      }
    end

    def suggest_performance_optimizations(execution)
      suggestions = []
      if execution.duration_ms && execution.duration_ms > 5000
        suggestions << "Consider using streaming responses for long operations"
      end
      if execution.tokens_used > 10_000
        suggestions << "High token usage (#{execution.tokens_used}). Consider reducing prompt size or using a more efficient model"
      end
      if execution.child_executions.count > 5
        suggestions << "#{execution.child_executions.count} child executions detected. Consider parallelizing independent tasks"
      end
      if execution.cost_usd > 0.1
        suggestions << "High cost ($#{execution.cost_usd.round(4)}). Consider using a smaller/cheaper model for this task"
      end
      suggestions
    end
  end
end
