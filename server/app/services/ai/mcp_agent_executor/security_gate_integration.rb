# frozen_string_literal: true

class Ai::McpAgentExecutor
  module SecurityGateIntegration
    extend ActiveSupport::Concern

    private

    # Run pre-execution security gate. Returns nil if allowed, or a block response hash.
    def run_pre_execution_security_gate(input_text, action_context = {})
      return nil unless @account

      gate = security_gate_service
      result = gate.pre_execution_gate(
        input_text: input_text,
        action_type: "execute",
        action_context: action_context.merge(agent_id: @agent.id)
      )

      return nil if result[:allowed]

      format_security_block(result)
    rescue StandardError => e
      @logger.error "[MCP_AGENT_EXECUTOR] Security gate error: #{e.message}"
      # Fail-closed: block execution on gate error
      format_security_block({
        allowed: false,
        blocked_by: :security_gate_error,
        checks: [{ name: :error, details: { error: e.message } }]
      })
    end

    # Run post-execution security gate. Returns nil if allowed, or modified result.
    def run_post_execution_security_gate(output_text)
      return nil unless @account

      gate = security_gate_service
      result = gate.post_execution_gate(
        output_text: output_text,
        execution_result: {}
      )

      return nil if result[:allowed] && result[:redacted_text].nil?

      if result[:allowed] && result[:redacted_text]
        # PII was redacted but output is allowed
        { redacted_text: result[:redacted_text] }
      elsif !result[:allowed]
        # Output blocked
        format_security_block(result)
      end
    rescue StandardError => e
      @logger.error "[MCP_AGENT_EXECUTOR] Post-execution security gate error: #{e.message}"
      nil # Don't block output on post-gate errors (output already generated)
    end

    # Record telemetry after execution completes
    def record_security_telemetry(result)
      return unless @account

      duration_ms = @start_time ? ((Time.current - @start_time) * 1000).round : 0
      cost_usd = result&.dig("cost_usd") || @execution&.cost_usd || 0.0
      tokens_used = result&.dig("tokens_used") || @execution&.tokens_used || 0

      security_gate_service.record_execution_telemetry(
        execution_result: result || {},
        duration_ms: duration_ms,
        cost_usd: cost_usd,
        tokens_used: tokens_used
      )
    rescue StandardError => e
      @logger.error "[MCP_AGENT_EXECUTOR] Security telemetry error: #{e.message}"
    end

    def format_security_block(gate_result)
      blocked_by = gate_result[:blocked_by]&.to_s || "security_gate"
      reason = gate_result[:checks]&.find { |c| c[:blocked] }&.dig(:details, :reason) || "Blocked by security gate"

      {
        "error" => {
          "code" => -32600,
          "message" => "Blocked by security gate (#{blocked_by}): #{reason}",
          "type" => "SecurityGateViolation",
          "timestamp" => Time.current.iso8601,
          "blocked_by" => blocked_by,
          "checks" => gate_result[:checks]&.map { |c| { name: c[:name], passed: c[:passed] } }
        },
        "tool_id" => @agent.mcp_tool_id,
        "execution_id" => @execution&.execution_id || SecureRandom.uuid
      }
    end

    def security_gate_service
      @security_gate_service ||= Ai::Security::SecurityGateService.new(
        account: @account,
        agent: @agent,
        execution: @execution
      )
    end
  end
end
