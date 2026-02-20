# frozen_string_literal: true

module Ai
  module Security
    class SecurityGateService
      # Orchestrator facade that unifies all security services into pre/post execution checks.
      # Wires the OWASP-aligned security stack into the agent execution pipeline.

      # Check criticality levels determine error-handling behavior:
      #   :hard    — fail-closed (block execution on error)
      #   :soft    — degraded mode (log warning, continue)
      #   :flag    — informational (log and continue)
      #   :telemetry — fire-and-forget (never blocks)
      CHECK_CONFIG = {
        quarantine_gate:   { criticality: :hard,      asi: "ASI08" },
        anomaly_precheck:  { criticality: :hard,      asi: "ASI01" },
        privilege_check:   { criticality: :hard,      asi: "ASI05" },
        conformance_check: { criticality: :soft,      asi: "ASI03" },
        prompt_injection:  { criticality: :hard,      asi: "ASI02" },
        pii_input_scan:    { criticality: :flag,      asi: "ASI04" },
        pii_output_redact: { criticality: :hard,      asi: "ASI04" },
        output_safety:     { criticality: :hard,      asi: "ASI09" }
      }.freeze

      class SecurityBlockError < StandardError
        attr_reader :check_name, :details

        def initialize(message, check_name:, details: {})
          @check_name = check_name
          @details = details
          super(message)
        end
      end

      def initialize(account:, agent:, execution: nil)
        @account = account
        @agent = agent
        @execution = execution
      end

      # Run all pre-execution security checks in order.
      # Returns { allowed: Boolean, blocked_by: String|nil, checks: Array, degraded: Boolean }
      def pre_execution_gate(input_text:, action_type: "execute", action_context: {})
        checks = []
        blocked = false
        blocked_by = nil
        degraded = false

        # 1. Quarantine gate
        result = run_check(:quarantine_gate) do
          quarantined = Ai::QuarantineRecord.where(agent_id: @agent.id, account: @account).active.exists?
          { passed: !quarantined, reason: quarantined ? "Agent is under active quarantine" : nil }
        end
        checks << result
        if result[:blocked]
          return gate_result(allowed: false, blocked_by: :quarantine_gate, checks: checks)
        end

        # 2. Anomaly pre-check
        result = run_check(:anomaly_precheck) do
          anomaly_service.check_action(
            agent: @agent,
            action_type: action_type,
            action_context: action_context
          )
        end
        checks << result
        if result[:blocked]
          return gate_result(allowed: false, blocked_by: :anomaly_precheck, checks: checks)
        end

        # 3. Privilege check
        result = run_check(:privilege_check) do
          privilege_service.check_action!(agent: @agent, action: action_type)
        end
        checks << result
        if result[:blocked]
          return gate_result(allowed: false, blocked_by: :privilege_check, checks: checks)
        end

        # 4. Conformance check (soft — degraded mode on violations)
        result = run_check(:conformance_check) do
          conformance = conformance_service.check_event(agent: @agent, event_type: "action_executed")
          high_violations = (conformance[:violations] || []).select { |v| %w[high critical].include?(v[:severity]) }
          { passed: high_violations.empty?, violations: conformance[:violations], reason: high_violations.first&.dig(:message) }
        end
        checks << result
        degraded = true unless result[:passed]

        # 5. Prompt injection detection
        result = run_check(:prompt_injection) do
          injection = anomaly_service.detect_prompt_injection(text: input_text)
          { passed: !injection[:detected] || injection[:confidence] < 0.8,
            detected: injection[:detected], confidence: injection[:confidence],
            reason: injection[:detected] ? "Prompt injection detected (confidence: #{injection[:confidence]})" : nil }
        end
        checks << result
        if result[:blocked]
          return gate_result(allowed: false, blocked_by: :prompt_injection, checks: checks)
        end

        # 6. PII input scan (informational — never blocks)
        result = run_check(:pii_input_scan) do
          scan = pii_service.scan(text: input_text)
          { passed: true, pii_found: scan[:pii_found], detections: scan[:detections]&.size || 0 }
        end
        checks << result

        gate_result(allowed: true, blocked_by: nil, checks: checks, degraded: degraded)
      end

      # Run post-execution security checks on output.
      # Returns { allowed: Boolean, blocked_by: String|nil, checks: Array, redacted_text: String|nil }
      def post_execution_gate(output_text:, execution_result: {})
        checks = []
        redacted_text = nil

        # 1. PII output redaction
        result = run_check(:pii_output_redact) do
          redaction = pii_service.redact(text: output_text, context: {
            source_type: "AgentOutput",
            source_id: @execution&.id || SecureRandom.uuid
          })
          redacted_text = redaction[:redacted_text] if redaction[:detections_count].to_i > 0
          { passed: true, redacted: redaction[:detections_count].to_i > 0, types: redaction[:types_found] }
        end
        checks << result

        # 2. Output safety check (is PII remaining after redaction?)
        text_to_check = redacted_text || output_text
        result = run_check(:output_safety) do
          safe = pii_service.safe_to_output?(text: text_to_check)
          { passed: safe, reason: safe ? nil : "PII remaining in output after redaction" }
        end
        checks << result
        if result[:blocked]
          return gate_result(allowed: false, blocked_by: :output_safety, checks: checks)
                   .merge(redacted_text: redacted_text)
        end

        gate_result(allowed: true, blocked_by: nil, checks: checks)
          .merge(redacted_text: redacted_text)
      end

      # Record execution telemetry (fire-and-forget, never blocks)
      def record_execution_telemetry(execution_result: {}, duration_ms: 0, cost_usd: 0.0, tokens_used: 0)
        # Behavioral fingerprint observations
        fingerprint_service.record_observation(agent: @agent, metric_name: "execution_duration_ms", value: duration_ms)
        fingerprint_service.record_observation(agent: @agent, metric_name: "execution_cost_usd", value: cost_usd) if cost_usd > 0
        fingerprint_service.record_observation(agent: @agent, metric_name: "tokens_used", value: tokens_used) if tokens_used > 0

        # Trust evaluation
        if @execution
          trust_service.evaluate(agent: @agent, execution: @execution)
        end

        # Conformance telemetry event
        if defined?(Ai::TelemetryEvent)
          Ai::TelemetryEvent.create(
            account_id: @account.id,
            agent_id: @agent.id,
            event_type: "action_executed",
            payload: {
              duration_ms: duration_ms,
              cost_usd: cost_usd,
              tokens_used: tokens_used,
              execution_id: @execution&.id
            }
          )
        end
      rescue StandardError => e
        Rails.logger.error "[SecurityGate] record_execution_telemetry error: #{e.message}"
      end

      private

      def run_check(name)
        config = CHECK_CONFIG[name]
        criticality = config[:criticality]

        check_result = yield
        passed = check_result[:passed] != false && check_result[:allowed] != false

        audit_check(name, passed, check_result, config[:asi])

        {
          name: name,
          passed: passed,
          blocked: !passed && criticality == :hard,
          degraded: !passed && criticality == :soft,
          flagged: !passed && %i[flag telemetry].include?(criticality),
          criticality: criticality,
          details: check_result
        }
      rescue StandardError => e
        Rails.logger.error "[SecurityGate] #{name} error: #{e.message}"

        case criticality
        when :hard
          # Fail-closed: treat error as a block
          { name: name, passed: false, blocked: true, degraded: false, flagged: false,
            criticality: criticality, details: { error: e.message, fail_closed: true } }
        when :soft
          { name: name, passed: false, blocked: false, degraded: true, flagged: false,
            criticality: criticality, details: { error: e.message } }
        else
          { name: name, passed: true, blocked: false, degraded: false, flagged: true,
            criticality: criticality, details: { error: e.message } }
        end
      end

      def gate_result(allowed:, blocked_by:, checks:, degraded: false)
        {
          allowed: allowed,
          blocked_by: blocked_by,
          checks: checks,
          degraded: degraded,
          check_count: checks.size,
          blocked_count: checks.count { |c| c[:blocked] },
          flagged_count: checks.count { |c| c[:flagged] }
        }
      end

      def audit_check(name, passed, details, asi_reference)
        Ai::SecurityAuditTrail.log!(
          action: "security_gate:#{name}",
          outcome: passed ? "allowed" : "blocked",
          account: @account,
          agent_id: @agent.id,
          asi_reference: asi_reference,
          csa_pillar: "behavior",
          source_service: "SecurityGateService",
          severity: passed ? "info" : "warning",
          details: { check: name, execution_id: @execution&.id }.merge(details.slice(:reason, :confidence, :detected, :pii_found))
        )
      rescue StandardError => e
        Rails.logger.error "[SecurityGate] audit_check failed: #{e.message}"
      end

      # Service memoizers
      def anomaly_service
        @anomaly_service ||= Ai::Security::AgentAnomalyDetectionService.new(account: @account)
      end

      def privilege_service
        @privilege_service ||= Ai::Security::PrivilegeEnforcementService.new(account: @account)
      end

      def conformance_service
        @conformance_service ||= Ai::Autonomy::ConformanceEngineService.new(account: @account)
      end

      def pii_service
        @pii_service ||= Ai::Security::PiiRedactionService.new(account: @account)
      end

      def fingerprint_service
        @fingerprint_service ||= Ai::Autonomy::BehavioralFingerprintService.new(account: @account)
      end

      def trust_service
        @trust_service ||= Ai::Autonomy::TrustEngineService.new(account: @account)
      end
    end
  end
end
