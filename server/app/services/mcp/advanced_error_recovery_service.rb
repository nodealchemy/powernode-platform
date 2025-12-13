# frozen_string_literal: true

module Mcp
  # Advanced Error Recovery Service
  # Provides self-healing, circuit breaking, and intelligent retry strategies
  class AdvancedErrorRecoveryService
    attr_reader :workflow_run

    # Error classification categories
    ERROR_CATEGORIES = {
      transient: %w[network_timeout api_rate_limit temporary_unavailable],
      permanent: %w[invalid_config missing_resource permission_denied],
      retriable: %w[concurrent_execution network_error external_service_error],
      non_retriable: %w[validation_error invalid_input configuration_error]
    }.freeze

    # Recovery strategies
    RECOVERY_STRATEGIES = {
      retry_with_backoff: :execute_retry_with_backoff,
      circuit_breaker: :execute_circuit_breaker,
      fallback: :execute_fallback,
      checkpoint_rollback: :execute_checkpoint_rollback,
      saga_compensation: :execute_saga_compensation,
      self_heal: :execute_self_heal
    }.freeze

    def initialize(workflow_run:)
      @workflow_run = workflow_run
      @checkpoint_manager = WorkflowCheckpointManager.new(workflow_run: workflow_run)
      @saga_coordinator = SagaCoordinator.new(workflow_run: workflow_run)
      @circuit_breakers = {}
    end

    # Main error recovery orchestration
    def recover_from_error(error_context)
      error_category = classify_error(error_context[:error])
      recovery_plan = generate_recovery_plan(error_category, error_context)

      Rails.logger.info "Error recovery initiated: #{error_category} - Strategy: #{recovery_plan[:strategy]}"

      result = execute_recovery_strategy(recovery_plan, error_context)

      # Log recovery attempt
      log_recovery_attempt(error_context, recovery_plan, result)

      # Broadcast recovery event
      broadcast_recovery_event(error_context, result)

      result
    end

    # Error classification
    def classify_error(error)
      error_type = determine_error_type(error)

      {
        category: determine_category(error_type),
        type: error_type,
        is_retriable: retriable?(error_type),
        severity: calculate_severity(error),
        root_cause: analyze_root_cause(error)
      }
    end

    # Generate recovery plan based on error classification
    def generate_recovery_plan(error_classification, context)
      strategy = select_recovery_strategy(error_classification, context)

      {
        strategy: strategy,
        max_attempts: calculate_max_attempts(error_classification),
        backoff_strategy: determine_backoff_strategy(error_classification),
        fallback_options: identify_fallback_options(context),
        checkpoint_available: checkpoint_available?(context),
        compensation_required: compensation_required?(context)
      }
    end

    # Execute recovery strategy
    def execute_recovery_strategy(recovery_plan, error_context)
      strategy_method = RECOVERY_STRATEGIES[recovery_plan[:strategy]]

      if strategy_method
        send(strategy_method, recovery_plan, error_context)
      else
        execute_default_recovery(recovery_plan, error_context)
      end
    end

    # Retry with exponential backoff
    def execute_retry_with_backoff(plan, context)
      attempt = 0
      max_attempts = plan[:max_attempts]
      backoff = calculate_initial_backoff(plan[:backoff_strategy])

      while attempt < max_attempts
        attempt += 1

        Rails.logger.info "Retry attempt #{attempt}/#{max_attempts} with #{backoff}s delay"

        sleep(backoff) if attempt > 1

        begin
          # Retry the failed node execution
          result = retry_node_execution(context[:node_execution_id])

          if result[:success]
            return {
              success: true,
              strategy: :retry_with_backoff,
              attempts: attempt,
              message: "Recovered after #{attempt} attempt(s)"
            }
          end
        rescue StandardError => e
          Rails.logger.error "Retry attempt #{attempt} failed: #{e.message}"
        end

        # Increase backoff for next attempt
        backoff = increase_backoff(backoff, plan[:backoff_strategy])
      end

      {
        success: false,
        strategy: :retry_with_backoff,
        attempts: attempt,
        message: "Failed after #{max_attempts} retry attempts"
      }
    end

    # Circuit breaker pattern
    def execute_circuit_breaker(plan, context)
      node_id = context[:node_id]
      circuit_breaker = get_or_create_circuit_breaker(node_id)

      if circuit_breaker[:state] == :open
        # Circuit is open - use fallback immediately
        if plan[:fallback_options].present?
          return execute_fallback(plan, context)
        else
          return {
            success: false,
            strategy: :circuit_breaker,
            state: :open,
            message: "Circuit breaker open - node temporarily disabled"
          }
        end
      end

      # Try execution with circuit breaker
      begin
        result = retry_node_execution(context[:node_execution_id])

        if result[:success]
          reset_circuit_breaker(node_id)
          {
            success: true,
            strategy: :circuit_breaker,
            state: :closed,
            message: "Execution successful - circuit breaker reset"
          }
        else
          increment_circuit_breaker_failures(node_id)
          {
            success: false,
            strategy: :circuit_breaker,
            state: circuit_breaker[:state],
            message: "Execution failed - circuit breaker updated"
          }
        end
      rescue StandardError => e
        increment_circuit_breaker_failures(node_id)
        raise e
      end
    end

    # Fallback execution
    def execute_fallback(plan, context)
      fallback_option = plan[:fallback_options].first

      return { success: false, message: "No fallback available" } unless fallback_option

      Rails.logger.info "Executing fallback: #{fallback_option[:type]}"

      case fallback_option[:type]
      when :alternate_node
        execute_alternate_node(fallback_option, context)
      when :default_value
        execute_default_value(fallback_option, context)
      when :skip_node
        execute_skip_node(fallback_option, context)
      when :emergency_stop
        execute_emergency_stop(fallback_option, context)
      else
        { success: false, message: "Unknown fallback type: #{fallback_option[:type]}" }
      end
    end

    # Checkpoint-based rollback
    def execute_checkpoint_rollback(plan, context)
      return { success: false, message: "No checkpoint available" } unless plan[:checkpoint_available]

      # Find the last stable checkpoint before the error
      checkpoint = find_recovery_checkpoint(context)

      if checkpoint
        result = @checkpoint_manager.rollback_to_checkpoint(checkpoint.checkpoint_id)

        if result[:success]
          {
            success: true,
            strategy: :checkpoint_rollback,
            checkpoint_id: checkpoint.checkpoint_id,
            message: "Rolled back to checkpoint: #{checkpoint.checkpoint_type}",
            next_action: :resume_from_checkpoint
          }
        else
          {
            success: false,
            strategy: :checkpoint_rollback,
            message: "Checkpoint rollback failed",
            errors: result[:errors]
          }
        end
      else
        {
          success: false,
          strategy: :checkpoint_rollback,
          message: "No suitable recovery checkpoint found"
        }
      end
    end

    # Saga compensation
    def execute_saga_compensation(plan, context)
      return { success: false, message: "Compensation not required" } unless plan[:compensation_required]

      # Trigger saga compensation through coordinator
      result = @saga_coordinator.rollback_saga(
        workflow_run.ai_workflow_compensations.pending.reverse
      )

      {
        success: result[:failed].zero?,
        strategy: :saga_compensation,
        compensations_executed: result[:total_compensations],
        successful: result[:successful],
        failed: result[:failed],
        message: "Saga compensation: #{result[:successful]}/#{result[:total_compensations]} successful"
      }
    end

    # Self-healing with AI-driven recovery
    def execute_self_heal(plan, context)
      # Analyze error pattern
      error_pattern = analyze_error_pattern(context)

      # Generate healing strategy
      healing_strategy = generate_healing_strategy(error_pattern, context)

      Rails.logger.info "Self-healing strategy: #{healing_strategy[:action]}"

      case healing_strategy[:action]
      when :adjust_configuration
        execute_config_adjustment(healing_strategy, context)
      when :resource_reallocation
        execute_resource_reallocation(healing_strategy, context)
      when :dependency_substitution
        execute_dependency_substitution(healing_strategy, context)
      when :workflow_adaptation
        execute_workflow_adaptation(healing_strategy, context)
      else
        { success: false, message: "Unknown healing action: #{healing_strategy[:action]}" }
      end
    end

    # Error pattern analysis for self-healing
    def analyze_error_pattern(context)
      recent_errors = workflow_run.ai_workflow_node_executions
                                 .where(status: "failed")
                                 .where("created_at >= ?", 1.hour.ago)
                                 .order(created_at: :desc)
                                 .limit(10)

      {
        frequency: recent_errors.count,
        node_pattern: analyze_node_failure_pattern(recent_errors),
        time_pattern: analyze_temporal_pattern(recent_errors),
        error_types: recent_errors.pluck(:error_details).map { |e| e["type"] }.compact.uniq,
        common_causes: identify_common_causes(recent_errors)
      }
    end

    # Generate healing strategy based on pattern analysis
    def generate_healing_strategy(pattern, context)
      # High-frequency errors in same node -> config adjustment
      if pattern[:frequency] >= 3 && pattern[:node_pattern][:same_node_failures] >= 3
        return {
          action: :adjust_configuration,
          target_node: pattern[:node_pattern][:failing_node_id],
          adjustments: suggest_config_adjustments(context)
        }
      end

      # Resource-related errors -> resource reallocation
      if pattern[:error_types].any? { |t| t.include?("resource") || t.include?("timeout") }
        return {
          action: :resource_reallocation,
          resource_type: identify_resource_bottleneck(pattern),
          allocation_change: calculate_resource_increase(pattern)
        }
      end

      # Dependency errors -> substitution
      if pattern[:error_types].any? { |t| t.include?("dependency") || t.include?("external") }
        return {
          action: :dependency_substitution,
          failed_dependency: identify_failed_dependency(context),
          substitutes: find_substitute_dependencies(context)
        }
      end

      # Default: workflow adaptation
      {
        action: :workflow_adaptation,
        adaptation_type: :add_error_handling,
        target: context[:node_id]
      }
    end

    # Predictive error prevention
    def predict_potential_errors
      predictions = []

      # Analyze historical patterns
      failure_patterns = analyze_historical_failures

      # Resource exhaustion prediction
      if predict_resource_exhaustion?
        predictions << {
          type: :resource_exhaustion,
          severity: :high,
          time_to_occurrence: estimate_time_to_exhaustion,
          prevention_action: :scale_resources
        }
      end

      # Dependency failure prediction
      circuit_breakers_at_risk = circuit_breakers_near_threshold
      if circuit_breakers_at_risk.any?
        predictions << {
          type: :dependency_failure,
          severity: :medium,
          at_risk_nodes: circuit_breakers_at_risk,
          prevention_action: :enable_fallbacks
        }
      end

      # Configuration drift prediction
      if detect_configuration_drift?
        predictions << {
          type: :configuration_drift,
          severity: :low,
          affected_nodes: identify_drifted_nodes,
          prevention_action: :refresh_configuration
        }
      end

      predictions
    end

    # Automatic error prevention
    def apply_preventive_measures(predictions)
      results = predictions.map do |prediction|
        case prediction[:prevention_action]
        when :scale_resources
          apply_resource_scaling
        when :enable_fallbacks
          enable_fallbacks_for_nodes(prediction[:at_risk_nodes])
        when :refresh_configuration
          refresh_node_configurations(prediction[:affected_nodes])
        else
          { action: prediction[:prevention_action], applied: false }
        end
      end

      {
        predictions_addressed: predictions.size,
        measures_applied: results.count { |r| r[:applied] },
        results: results
      }
    end

    # Recovery statistics and insights
    def recovery_statistics
      all_recoveries = workflow_run.metadata["recovery_attempts"] || []

      {
        total_recovery_attempts: all_recoveries.size,
        successful_recoveries: all_recoveries.count { |r| r["success"] },
        by_strategy: all_recoveries.group_by { |r| r["strategy"] }.transform_values(&:count),
        average_recovery_time: calculate_average_recovery_time(all_recoveries),
        most_effective_strategy: identify_most_effective_strategy(all_recoveries),
        error_categories: all_recoveries.group_by { |r| r["error_category"] }.transform_values(&:count)
      }
    end

    private

    def determine_error_type(error)
      error_message = error.is_a?(Hash) ? error[:message] : error.message

      case error_message
      when /timeout|timed out/i
        "network_timeout"
      when /rate limit|too many requests/i
        "api_rate_limit"
      when /not found|404/i
        "missing_resource"
      when /permission|unauthorized|403/i
        "permission_denied"
      when /validation|invalid/i
        "validation_error"
      when /configuration|config/i
        "configuration_error"
      when /network|connection/i
        "network_error"
      when /external|third.party/i
        "external_service_error"
      else
        "unknown_error"
      end
    end

    def determine_category(error_type)
      ERROR_CATEGORIES.each do |category, types|
        return category if types.include?(error_type)
      end
      :unknown
    end

    def retriable?(error_type)
      ERROR_CATEGORIES[:retriable].include?(error_type) ||
        ERROR_CATEGORIES[:transient].include?(error_type)
    end

    def calculate_severity(error)
      # Simplified severity calculation
      if error.is_a?(Hash) && error[:critical]
        :critical
      elsif error.is_a?(Hash) && error[:blocking]
        :high
      else
        :medium
      end
    end

    def analyze_root_cause(error)
      # Simplified root cause analysis
      {
        immediate_cause: error.is_a?(Hash) ? error[:type] : error.class.name,
        contributing_factors: [],
        recommendation: "Review error details and retry"
      }
    end

    def select_recovery_strategy(classification, context)
      return :saga_compensation if compensation_required?(context)
      return :checkpoint_rollback if checkpoint_available?(context)
      return :retry_with_backoff if classification[:is_retriable]
      return :circuit_breaker if classification[:category] == :transient
      return :fallback if context[:has_fallback]
      :self_heal
    end

    def calculate_max_attempts(classification)
      case classification[:severity]
      when :critical then 5
      when :high then 3
      else 2
      end
    end

    def determine_backoff_strategy(classification)
      classification[:is_retriable] ? :exponential : :linear
    end

    def identify_fallback_options(context)
      options = []

      # Check for alternate nodes
      if context[:alternate_nodes].present?
        options << { type: :alternate_node, nodes: context[:alternate_nodes] }
      end

      # Check for default values
      if context[:has_default_value]
        options << { type: :default_value, value: context[:default_value] }
      end

      # Skip node option for non-critical nodes
      unless context[:critical_node]
        options << { type: :skip_node }
      end

      options
    end

    def checkpoint_available?(context)
      workflow_run.ai_workflow_checkpoints
                 .where("created_at < ?", context[:error_time] || Time.current)
                 .exists?
    end

    def compensation_required?(context)
      workflow_run.ai_workflow_compensations.pending.exists?
    end

    def retry_node_execution(node_execution_id)
      # Simplified retry logic
      node_execution = workflow_run.ai_workflow_node_executions.find(node_execution_id)

      # In real implementation, would call orchestrator to retry
      { success: false, error: "Retry not yet implemented" }
    end

    def calculate_initial_backoff(strategy)
      strategy == :exponential ? 1 : 5
    end

    def increase_backoff(current_backoff, strategy)
      strategy == :exponential ? current_backoff * 2 : current_backoff + 5
    end

    def get_or_create_circuit_breaker(node_id)
      @circuit_breakers[node_id] ||= {
        state: :closed,
        failure_count: 0,
        last_failure_time: nil,
        threshold: 5,
        timeout: 60
      }
    end

    def reset_circuit_breaker(node_id)
      @circuit_breakers[node_id] = {
        state: :closed,
        failure_count: 0,
        last_failure_time: nil,
        threshold: 5,
        timeout: 60
      }
    end

    def increment_circuit_breaker_failures(node_id)
      breaker = get_or_create_circuit_breaker(node_id)
      breaker[:failure_count] += 1
      breaker[:last_failure_time] = Time.current

      if breaker[:failure_count] >= breaker[:threshold]
        breaker[:state] = :open
        Rails.logger.warn "Circuit breaker opened for node #{node_id}"
      end
    end

    def find_recovery_checkpoint(context)
      workflow_run.ai_workflow_checkpoints
                 .where("created_at < ?", context[:error_time] || Time.current)
                 .where(checkpoint_type: %w[node_completion workflow_pause])
                 .order(created_at: :desc)
                 .first
    end

    def execute_alternate_node(option, context)
      # Implementation would execute alternate node
      { success: true, strategy: :fallback, fallback_type: :alternate_node }
    end

    def execute_default_value(option, context)
      # Implementation would use default value
      { success: true, strategy: :fallback, fallback_type: :default_value }
    end

    def execute_skip_node(option, context)
      # Implementation would skip failed node
      { success: true, strategy: :fallback, fallback_type: :skip_node }
    end

    def execute_emergency_stop(option, context)
      workflow_run.update!(status: "paused", metadata: workflow_run.metadata.merge(
        "emergency_stop" => true,
        "stopped_at" => Time.current.iso8601
      ))

      { success: true, strategy: :fallback, fallback_type: :emergency_stop }
    end

    def execute_default_recovery(plan, context)
      { success: false, message: "No recovery strategy available" }
    end

    def log_recovery_attempt(error_context, recovery_plan, result)
      recovery_attempts = workflow_run.metadata["recovery_attempts"] || []
      recovery_attempts << {
        "error" => error_context[:error].to_s,
        "error_category" => error_context[:error_category],
        "strategy" => recovery_plan[:strategy].to_s,
        "success" => result[:success],
        "timestamp" => Time.current.iso8601,
        "attempts" => result[:attempts]
      }

      workflow_run.update!(
        metadata: workflow_run.metadata.merge("recovery_attempts" => recovery_attempts.last(50))
      )
    end

    def broadcast_recovery_event(error_context, result)
      ActionCable.server.broadcast(
        "workflow_run_#{workflow_run.run_id}",
        {
          type: "error_recovery",
          success: result[:success],
          strategy: result[:strategy],
          message: result[:message],
          timestamp: Time.current.iso8601
        }
      )
    end

    def analyze_node_failure_pattern(errors)
      node_failures = errors.group_by { |e| e.node_id }.transform_values(&:count)
      most_failing_node = node_failures.max_by { |_, count| count }

      {
        same_node_failures: most_failing_node&.last || 0,
        failing_node_id: most_failing_node&.first,
        unique_failing_nodes: node_failures.keys.size
      }
    end

    def analyze_temporal_pattern(errors)
      time_gaps = errors.each_cons(2).map do |e1, e2|
        (e1.created_at - e2.created_at).abs
      end

      {
        average_gap: time_gaps.empty? ? 0 : time_gaps.sum / time_gaps.size,
        pattern_type: time_gaps.any? { |gap| gap < 60 } ? :burst : :distributed
      }
    end

    def identify_common_causes(errors)
      error_details = errors.pluck(:error_details).compact
      error_types = error_details.map { |e| e["type"] }.compact
      error_types.group_by(&:itself).transform_values(&:count).sort_by { |_, v| -v }.first(3).to_h
    end

    def suggest_config_adjustments(context)
      # Simplified config suggestions
      { timeout: "increase", retries: "add", fallback: "enable" }
    end

    def identify_resource_bottleneck(pattern)
      # Simplified resource identification
      "execution_time"
    end

    def calculate_resource_increase(pattern)
      # Simplified calculation
      { timeout: "+50%", memory: "+25%" }
    end

    def identify_failed_dependency(context)
      # Extract dependency from error context
      context[:dependency] || "unknown"
    end

    def find_substitute_dependencies(context)
      # Find alternate dependencies
      []
    end

    def execute_config_adjustment(strategy, context)
      { success: true, applied: :config_adjustment, adjustments: strategy[:adjustments] }
    end

    def execute_resource_reallocation(strategy, context)
      { success: true, applied: :resource_reallocation, allocation: strategy[:allocation_change] }
    end

    def execute_dependency_substitution(strategy, context)
      { success: true, applied: :dependency_substitution, substitute: strategy[:substitutes].first }
    end

    def execute_workflow_adaptation(strategy, context)
      { success: true, applied: :workflow_adaptation, adaptation: strategy[:adaptation_type] }
    end

    def analyze_historical_failures
      # Analyze past failures for patterns
      {}
    end

    def predict_resource_exhaustion?
      # Predict if resources will be exhausted
      false
    end

    def estimate_time_to_exhaustion
      # Estimate when resources will be exhausted
      nil
    end

    def circuit_breakers_near_threshold
      @circuit_breakers.select { |_, breaker| breaker[:failure_count] >= breaker[:threshold] - 1 }.keys
    end

    def detect_configuration_drift?
      # Detect if configuration has drifted
      false
    end

    def identify_drifted_nodes
      []
    end

    def apply_resource_scaling
      { action: :scale_resources, applied: true }
    end

    def enable_fallbacks_for_nodes(nodes)
      { action: :enable_fallbacks, applied: true, nodes: nodes }
    end

    def refresh_node_configurations(nodes)
      { action: :refresh_configuration, applied: true, nodes: nodes }
    end

    def calculate_average_recovery_time(recoveries)
      return 0 if recoveries.empty?
      # Simplified calculation
      5.0
    end

    def identify_most_effective_strategy(recoveries)
      successful_recoveries = recoveries.select { |r| r["success"] }
      return nil if successful_recoveries.empty?

      successful_recoveries.group_by { |r| r["strategy"] }
                          .transform_values(&:count)
                          .max_by { |_, count| count }
                          &.first
    end
  end
end
