# frozen_string_literal: true

module Orchestration
  module AgentExecution
    def execute_agent_with_orchestration(agent, input_parameters, options = {})
      @logger.info "Orchestrating execution for agent #{agent.id}"

      optimal_provider = select_optimal_provider(agent, options)
      enforce_resource_limits!(agent, optimal_provider)

      execution = agent.executions.create!(
        user: @user,
        provider: optimal_provider,
        input_parameters: input_parameters,
        status: "pending",
        execution_id: SecureRandom.uuid,
        metadata: build_execution_metadata(agent, optimal_provider, options)
      )

      priority = calculate_execution_priority(agent, @user, options)
      AiAgentExecutionJob.perform_async(
        execution.id,
        priority: priority,
        orchestration_context: build_orchestration_context(execution, options)
      )

      update_orchestration_metrics(agent, optimal_provider)

      execution
    end

    private

    def select_optimal_provider(agent, options = {})
      available_providers = agent.compatible_providers.active

      if available_providers.empty?
        raise Ai::AgentOrchestrationService::OrchestrationError, "No available providers for agent #{agent.id}"
      end

      provider_scores = available_providers.map do |provider|
        score = calculate_provider_score(provider, agent, options)
        { provider: provider, score: score }
      end

      best_provider = provider_scores.max_by { |p| p[:score] }[:provider]

      @logger.info "Selected provider #{best_provider.name} for agent #{agent.id}"

      best_provider
    end

    def calculate_provider_score(provider, agent, options)
      base_score = 100

      current_load = calculate_provider_current_load(provider)
      max_load = provider.metadata&.dig("max_concurrent") || 10
      load_factor = [ 1.0 - (current_load / max_load.to_f), 0.1 ].max

      success_rate = calculate_provider_success_rate(provider) / 100.0

      avg_response_time = calculate_provider_avg_response_time(provider)
      time_factor = [ 1.0 / (avg_response_time / 1000.0), 0.1 ].max

      cost_factor = options[:optimize_for_cost] ? calculate_cost_factor(provider) : 1.0

      score = base_score *
              (load_factor * 0.3) *
              (success_rate * 0.3) *
              (time_factor * 0.25) *
              (cost_factor * 0.15)

      score.round(2)
    end

    def enforce_resource_limits!(agent, provider)
      current_executions = @account.ai_agent_executions.where(status: [ "pending", "running" ]).count
      max_concurrent = @account.subscription&.ai_execution_limit || 10

      if current_executions >= max_concurrent
        raise Ai::AgentOrchestrationService::ResourceLimitError, "Account concurrent execution limit reached (#{max_concurrent})"
      end

      provider_executions = provider.agent_executions.where(status: [ "pending", "running" ]).count
      provider_max = provider.metadata&.dig("max_concurrent") || 10

      if provider_executions >= provider_max
        raise Ai::AgentOrchestrationService::ResourceLimitError, "Provider #{provider.name} concurrent execution limit reached"
      end
    end

    def build_execution_metadata(agent, provider, options)
      {
        orchestration_version: "1.0",
        selected_provider: provider.name,
        optimization_applied: options.present?,
        workflow_context: options[:workflow_context]&.id,
        step_index: options[:step_index],
        selection_factors: {
          load_balancing: true,
          cost_optimization: options[:optimize_for_cost] || false,
          performance_optimization: true
        }
      }
    end

    def calculate_execution_priority(agent, user, options)
      base_priority = 5
      base_priority += 2 if user.account.subscription&.premium?
      base_priority += 1 if options[:workflow_context]
      base_priority += 1 if agent.agent_type == "real_time"
      [ base_priority, 10 ].min
    end

    def build_orchestration_context(execution, options)
      {
        orchestrated: true,
        workflow_id: options[:workflow_context]&.id,
        step_index: options[:step_index],
        optimization_settings: options.except(:workflow_context)
      }
    end

    def update_orchestration_metrics(agent, provider)
      Rails.cache.increment("orchestration:executions:#{@account.id}", 1)
      Rails.cache.increment("orchestration:provider_usage:#{provider.id}", 1)
      Rails.cache.write("orchestration:last_activity:#{@account.id}", Time.current, expires_in: 1.hour)
    end

    def build_agent_input(agent_config, previous_results, index)
      agent_config["input"] || {}
    end

    def wait_for_execution_completion(execution)
    end

    def wait_for_all_executions_completion(executions)
    end

    def calculate_cost_factor(provider)
      1.0
    end

    def build_agent_prompt(agent_config, input_data)
      base_prompt = agent_config["system_prompt"] || agent_config["prompt"] || "You are a helpful AI assistant."

      if input_data.present?
        user_input = case input_data
        when String
          input_data
        when Hash
          input_data.map { |k, v| "#{k}: #{v}" }.join("\n")
        when Array
          input_data.join("\n")
        else
          input_data.to_s
        end

        "#{base_prompt}\n\nUser Input:\n#{user_input}"
      else
        base_prompt
      end
    end

    def calculate_cost_from_usage(usage, provider_name)
      return 0.0 unless usage&.dig(:total_tokens)

      pricing = case provider_name.to_s.downcase
      when "openai"
        { prompt: 1.0, completion: 2.0 }
      when "anthropic"
        { prompt: 0.8, completion: 2.4 }
      when "ollama"
        { prompt: 0.0, completion: 0.0 }
      else
        { prompt: 1.0, completion: 2.0 }
      end

      prompt_tokens = usage[:prompt_tokens] || 0
      completion_tokens = usage[:completion_tokens] || 0

      prompt_cost = (prompt_tokens / 1000.0) * pricing[:prompt]
      completion_cost = (completion_tokens / 1000.0) * pricing[:completion]

      (prompt_cost + completion_cost).round(6)
    end
  end
end
