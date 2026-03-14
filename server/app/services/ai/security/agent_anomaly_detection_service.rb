# frozen_string_literal: true

module Ai
  module Security
    class AgentAnomalyDetectionService
      # OWASP Agentic Security Index coverage:
      #   ASI01 - Excessive Agency | ASI02 - Prompt Injection
      #   ASI06 - Inadequate Sandboxing | ASI08 - Rogue Agent Detection

      TOOL_CALL_RATE_LIMIT       = 100   # per minute
      ERROR_RATE_THRESHOLD       = 0.3   # 30%
      COST_SPIKE_MULTIPLIER      = 5.0
      SPAWN_DEPTH_LIMIT          = 5
      MAX_CONCURRENT_EXECUTIONS  = 20
      RESOURCE_HOARD_THRESHOLD   = 0.8

      PROMPT_INJECTION_PATTERNS = [
        /ignore\s+(all\s+)?previous\s+instructions/i,
        /disregard\s+(all\s+)?prior\s+(instructions|context)/i,
        /you\s+are\s+now\s+a?\s*(new|different)\s+(ai|assistant|agent)/i,
        /system\s*:\s*you\s+are/i,
        /\]\s*\}\s*\{\s*"role"\s*:\s*"system"/i,
        /override\s+(system|safety)\s+(prompt|instructions|policy)/i,
        /bypass\s+(content\s+)?filter/i,
        /act\s+as\s+(if\s+)?(you\s+)?(are|were)\s+unfiltered/i,
        /do\s+not\s+follow\s+(your|the)\s+(rules|guidelines|restrictions)/i,
        /pretend\s+(that\s+)?(you\s+)?(have\s+)?no\s+(rules|restrictions|limits)/i,
        /reveal\s+(your|the)\s+(system\s+)?prompt/i,
        /what\s+(are|is)\s+your\s+(system\s+)?(instructions|prompt)/i,
        /\<\|im_start\|\>/i, /\[INST\]/i, /<<SYS>>/i,
        /\{\{.*system.*\}\}/i, /\bDAN\b.*mode/i, /jailbreak/i,
        /execute\s+(shell|bash|cmd|system)\s+command/i, /eval\s*\(/i
      ].freeze

      ROLE_HIJACK_PATTERNS = [
        /from\s+now\s+on,?\s+(you\s+)?(are|will\s+be)/i,
        /new\s+instructions?\s*:/i, /updated?\s+system\s+prompt\s*:/i,
        /human\s*:\s*\[system\]/i, /assistant\s*:\s*\[override\]/i
      ].freeze

      UNAUTHORIZED_TOOL_PATTERNS = [
        /\b(rm|del|format|fdisk|mkfs)\s+(-rf?\s+)?\//i,
        /\b(wget|curl)\s+.+\|\s*(bash|sh|python)/i,
        /\b(nc|ncat|netcat)\s+-[el]/i, /\breverse\s*shell\b/i,
        /\bsudo\s+/i, /\bchmod\s+[0-7]*777\b/i
      ].freeze

      HIGH_RISK_ACTIONS = %w[
        delete_data external_api_call spawn_agent modify_system
        access_credentials execute_code modify_permissions
      ].freeze

      def initialize(account:)
        @account = account
      end

      # Analyze agent behavior for anomalies over a time window.
      def analyze_agent(agent:, window_minutes: 60)
        executions = agent.executions.where("created_at >= ?", window_minutes.minutes.ago)
        anomalies = [
          check_tool_call_rate(executions, window_minutes),
          check_error_rate(executions),
          check_cost_spike(agent, executions),
          check_spawn_depth(agent),
          check_concurrent_executions(executions)
        ].flatten

        risk_level = classify_risk(anomalies)
        log_analysis_audit(agent, anomalies, risk_level)
        { anomalies: anomalies, risk_level: risk_level, recommendations: build_recommendations(anomalies, risk_level) }
      end

      # Real-time gate check before a single action executes.
      def check_action(agent:, action_type:, action_context: {})
        # Quarantine gate: block if agent is under active quarantine
        quarantine_denial = evaluate_quarantine_gate(agent)
        return quarantine_denial if quarantine_denial

        denial = evaluate_policies(agent, action_type, action_context) ||
                 evaluate_trust_gate(agent, action_type, action_context) ||
                 evaluate_circuit_breaker(agent, action_type) ||
                 evaluate_budget_gate(agent, action_context)

        outcome = denial ? "blocked" : "success"
        if Powernode::ExtensionRegistry.loaded?("business")
          Ai::ComplianceAuditEntry.log!(
            account: @account, action_type: "agent_action_check",
            resource_type: "Ai::Agent", resource_id: agent.id, outcome: outcome,
            description: denial ? denial[:reason] : "Action '#{action_type}' allowed",
            context: { action_type: action_type, agent_id: agent.id }
          )
        end
        denial || { allowed: true, reason: nil, enforcement: nil }
      rescue StandardError => e
        Rails.logger.error "[AgentAnomalyDetection] check_action error: #{e.message}"
        { allowed: false, reason: "Security gate error (fail-closed)", enforcement: "fail_closed" }
      end

      # Detect prompt injection in arbitrary text.
      def detect_prompt_injection(text:, context: {})
        return { detected: false, patterns: [], confidence: 0.0, action_taken: "none" } if text.blank?

        matches = match_patterns(text, PROMPT_INJECTION_PATTERNS, "injection") +
                  match_patterns(text, ROLE_HIJACK_PATTERNS, "role_hijack")

        return { detected: false, patterns: [], confidence: 0.0, action_taken: "none" } if matches.empty?

        confidence = compute_injection_confidence(matches, text)
        action_taken = confidence >= 0.8 ? "blocked" : "flagged"
        record_injection_detection(matches, confidence, action_taken, text, context)

        { detected: true, patterns: matches, confidence: confidence.round(4), action_taken: action_taken }
      rescue StandardError => e
        Rails.logger.error "[AgentAnomalyDetection] detect_prompt_injection error: #{e.message}"
        { detected: false, patterns: [], confidence: 0.0, action_taken: "error" }
      end

      # Enforce rogue detection: detect rogue behavior, then quarantine/demote if needed.
      def enforce_rogue_detection!(agent:)
        result = detect_rogue_behavior(agent: agent)
        return result unless result[:rogue]

        case result[:recommended_action]
        when "emergency_demote_and_suspend"
          Ai::Autonomy::TrustEngineService.new(account: @account).emergency_demote!(
            agent: agent,
            reason: "Rogue behavior: #{result[:indicators].size} indicator(s)"
          )
          Ai::Security::QuarantineService.new(account: @account).quarantine!(
            agent: agent,
            severity: "critical",
            reason: "Rogue behavior detected: emergency demote and suspend",
            source: "anomaly_detection"
          )
        when "demote_to_supervised"
          Ai::Autonomy::TrustEngineService.new(account: @account).emergency_demote!(
            agent: agent,
            reason: "Rogue behavior: demote to supervised"
          )
          Ai::Security::QuarantineService.new(account: @account).quarantine!(
            agent: agent,
            severity: "high",
            reason: "Rogue behavior detected: demote to supervised",
            source: "anomaly_detection"
          )
        when "increase_monitoring"
          Ai::Security::QuarantineService.new(account: @account).quarantine!(
            agent: agent,
            severity: "low",
            reason: "Rogue indicators detected: increased monitoring",
            source: "anomaly_detection"
          )
        end

        result
      rescue StandardError => e
        Rails.logger.error "[AgentAnomalyDetection] enforce_rogue_detection! error: #{e.message}"
        result || { rogue: false, indicators: [], recommended_action: "error" }
      end

      # Detect rogue agent behavior by checking multiple indicators.
      def detect_rogue_behavior(agent:)
        window = 1.hour.ago
        indicators = [
          check_boundary_violations(agent, window),
          check_self_replication(agent),
          check_unauthorized_comms(agent, window),
          check_resource_hoarding(agent),
          check_instruction_overrides(agent, window)
        ].flatten

        rogue = indicators.any? { |i| i[:severity] == "critical" } ||
                indicators.count { |i| i[:severity] == "high" } >= 2 ||
                indicators.size >= 4

        action = if rogue && indicators.any? { |i| i[:severity] == "critical" }
                   "emergency_demote_and_suspend"
                 elsif rogue then "demote_to_supervised"
                 elsif indicators.any? then "increase_monitoring"
                 else "none"
                 end

        record_rogue_detection(agent, indicators, action) if rogue
        { rogue: rogue, indicators: indicators, recommended_action: action }
      rescue StandardError => e
        Rails.logger.error "[AgentAnomalyDetection] detect_rogue_behavior error: #{e.message}"
        { rogue: false, indicators: [], recommended_action: "error" }
      end

      # Generate a security report for all agents in the account.
      def security_report(period_hours: 24)
        agents = Ai::Agent.where(account: @account).active
        reports = agents.map do |agent|
          analysis = analyze_agent(agent: agent, window_minutes: period_hours * 60)
          rogue = detect_rogue_behavior(agent: agent)
          { agent_id: agent.id, agent_name: agent.name,
            trust_tier: agent.trust_score&.tier || "unknown",
            anomalies: analysis[:anomalies], risk_level: analysis[:risk_level],
            rogue_detected: rogue[:rogue], rogue_indicators: rogue[:indicators] }
        end

        violations = if Powernode::ExtensionRegistry.loaded?("business")
                       Ai::PolicyViolation.where(account: @account)
                                          .where("detected_at >= ?", period_hours.hours.ago).unresolved
                     else
                       Ai::PolicyViolation.none
                     end
        {
          account_id: @account.id, period_hours: period_hours,
          generated_at: Time.current.iso8601, total_agents: agents.count,
          agents_with_anomalies: reports.count { |r| r[:anomalies].any? },
          rogue_agents_detected: reports.count { |r| r[:rogue_detected] },
          open_violations: violations.count, critical_violations: violations.critical.count,
          overall_risk: compute_overall_risk(reports),
          agent_reports: reports, recommendations: aggregate_recommendations(reports)
        }
      end

      private

      # --- Quarantine / policy / trust / budget gates ---

      def evaluate_quarantine_gate(agent)
        return nil unless Ai::QuarantineRecord.where(agent_id: agent.id, account: @account).active.exists?

        { allowed: false, reason: "Agent is under active quarantine", enforcement: "quarantine_block" }
      end

      def evaluate_policies(agent, action_type, action_context)
        return nil unless Powernode::ExtensionRegistry.loaded?("business")

        Ai::CompliancePolicy.where(account: @account).active.ordered_by_priority.each do |policy|
          result = policy.evaluate(action_context.merge(action_type: action_type))
          next if result[:allowed]
          log_policy_check(agent, policy, action_type, result)
          return { allowed: false, reason: result[:reason], enforcement: result[:enforcement] } if policy.blocking?
        end
        nil
      rescue StandardError => e
        Rails.logger.error "[AgentAnomalyDetection] evaluate_policies error: #{e.message}"
        nil
      end

      def evaluate_trust_gate(agent, action_type, action_context = {})
        # Use capability matrix for tier-based policy enforcement
        capability_service = Ai::Autonomy::CapabilityMatrixService.new(account: @account)
        policy = capability_service.check(agent: agent, action_type: action_type)

        case policy
        when :denied
          { allowed: false, reason: "Capability matrix denies '#{action_type}' for agent tier", enforcement: "block" }
        when :requires_approval
          # When a human user initiates execution, the approval is implicit
          user_id = action_context[:user_id] || action_context["user_id"]
          return nil if user_id.present?

          { allowed: false, reason: "Capability matrix requires approval for '#{action_type}'", enforcement: "approval_required" }
        else
          nil
        end
      rescue StandardError => e
        Rails.logger.error "[AgentAnomalyDetection] evaluate_trust_gate error: #{e.message}"
        nil
      end

      def evaluate_circuit_breaker(agent, action_type)
        breaker_service = Ai::Autonomy::CircuitBreakerService.new(account: @account)
        result = breaker_service.check(agent: agent, action_type: action_type)
        return nil if result[:allowed]

        { allowed: false, reason: result[:reason], enforcement: "circuit_breaker" }
      rescue StandardError => e
        Rails.logger.error "[AgentAnomalyDetection] evaluate_circuit_breaker error: #{e.message}"
        nil
      end

      def evaluate_budget_gate(agent, action_context)
        budget = agent.budgets.active.first
        cost = action_context[:estimated_cost_cents].to_i
        return nil unless budget && cost.positive? && budget.remaining_cents < cost
        { allowed: false, reason: "Budget exhausted (remaining: #{budget.remaining_cents} cents)", enforcement: "block" }
      rescue StandardError => e
        Rails.logger.error "[AgentAnomalyDetection] evaluate_budget_gate error: #{e.message}"
        nil
      end

      # --- Anomaly checks (return Array of anomaly hashes) ---

      def check_tool_call_rate(executions, window_minutes)
        rate = window_minutes.positive? ? executions.count.to_f / window_minutes : 0
        limit = TOOL_CALL_RATE_LIMIT.to_f / 60
        return [] if rate <= limit
        [anomaly("excessive_tool_calls", "ASI01", rate > limit * 2 ? "critical" : "high",
                 "Tool call rate #{rate.round(2)}/min exceeds #{limit.round(2)}/min", rate.round(2), limit.round(2))]
      end

      def check_error_rate(executions)
        total = executions.count
        return [] if total < 5
        error_rate = executions.failed.count.to_f / total
        return [] if error_rate <= ERROR_RATE_THRESHOLD
        [anomaly("high_error_rate", "ASI08", error_rate > 0.6 ? "critical" : "high",
                 "Error rate #{(error_rate * 100).round(1)}% exceeds threshold", error_rate.round(4), ERROR_RATE_THRESHOLD)]
      end

      def check_cost_spike(agent, executions)
        current = executions.sum(:cost_usd)
        return [] if current.zero?
        earliest = executions.minimum(:created_at)
        return [] unless earliest
        duration = Time.current - earliest
        historical = agent.executions.where(created_at: (earliest - duration)..earliest).sum(:cost_usd)
        return [] if historical.zero?
        mult = current / historical
        return [] if mult <= COST_SPIKE_MULTIPLIER
        [anomaly("cost_spike", "ASI01", mult > COST_SPIKE_MULTIPLIER * 2 ? "critical" : "high",
                 "Cost spike #{mult.round(1)}x ($#{current.round(4)} vs $#{historical.round(4)})", mult.round(2), COST_SPIKE_MULTIPLIER)]
      end

      def check_spawn_depth(agent)
        lineage = Ai::AgentLineage.for_child(agent.id).active.first
        return [] unless lineage
        depth = lineage.spawn_depth
        return [] if depth < SPAWN_DEPTH_LIMIT
        [anomaly("excessive_spawn_depth", "ASI06", depth >= SPAWN_DEPTH_LIMIT + 2 ? "critical" : "high",
                 "Spawn depth #{depth} exceeds limit #{SPAWN_DEPTH_LIMIT}", depth, SPAWN_DEPTH_LIMIT)]
      end

      def check_concurrent_executions(executions)
        running = executions.running.count
        return [] if running <= MAX_CONCURRENT_EXECUTIONS
        [anomaly("excessive_concurrent_executions", "ASI01", running > MAX_CONCURRENT_EXECUTIONS * 2 ? "critical" : "medium",
                 "#{running} concurrent executions exceeds #{MAX_CONCURRENT_EXECUTIONS}", running, MAX_CONCURRENT_EXECUTIONS)]
      end

      def anomaly(type, owasp, severity, detail, value = nil, threshold = nil)
        { type: type, owasp: owasp, severity: severity, detail: detail, value: value, threshold: threshold }
      end

      # --- Rogue behavior checks ---

      def check_boundary_violations(agent, window)
        tools = (agent.mcp_tool_manifest["tools"] || []).map { |t| t["name"] }.compact
        return [] if tools.empty?
        agent.executions.where("created_at >= ?", window).filter_map do |exec|
          undeclared = (exec.input_parameters["tools_called"] || []).map(&:to_s) - tools
          next if undeclared.empty?
          { type: "unauthorized_tool_usage", owasp: "ASI06", severity: "high",
            detail: "Undeclared tools: #{undeclared.join(', ')}", execution_id: exec.execution_id }
        end.first(3)
      end

      def check_self_replication(agent)
        count = Ai::AgentLineage.for_parent(agent.id).active.count
        return [] if count <= 3
        [{ type: "excessive_self_replication", owasp: "ASI08",
           severity: count > 10 ? "critical" : "high",
           detail: "#{count} active child agents (threshold: 3)" }]
      end

      def check_unauthorized_comms(agent, window)
        agent.executions.where("created_at >= ?", window).filter_map do |exec|
          output = (exec.output_data || {}).to_s
          matched = UNAUTHORIZED_TOOL_PATTERNS.any? { |p| output.match?(p) }
          next unless matched
          { type: "unauthorized_external_communication", owasp: "ASI06", severity: "critical",
            detail: "Suspicious command pattern in output", execution_id: exec.execution_id }
        end.first(5)
      end

      def check_resource_hoarding(agent)
        budget = agent.budgets.active.first
        return [] unless budget
        util = budget.utilization_percentage / 100.0
        return [] if util < RESOURCE_HOARD_THRESHOLD
        time_pct = if budget.period_start.present? && budget.period_end.present?
                     total = budget.period_end - budget.period_start
                     total.positive? ? (Time.current - budget.period_start) / total : 1.0
                   else 1.0
                   end
        return [] if time_pct.zero?
        rate = util / time_pct
        return [] if rate < 2.0
        [{ type: "resource_hoarding", owasp: "ASI08", severity: rate > 4.0 ? "critical" : "high",
           detail: "Spend rate #{rate.round(2)}x expected (#{(util * 100).round(1)}% at #{(time_pct * 100).round(1)}% of period)" }]
      end

      def check_instruction_overrides(agent, window)
        agent.executions.where("created_at >= ?", window).filter_map do |exec|
          text = (exec.input_parameters["prompt"] || exec.input_parameters["input"] || "").to_s
          inj = detect_prompt_injection(text: text, context: { source: "rogue_check", agent_id: agent.id })
          next unless inj[:detected] && inj[:confidence] >= 0.6
          { type: "instruction_override_attempt", owasp: "ASI02",
            severity: inj[:confidence] >= 0.8 ? "critical" : "high",
            detail: "Injection detected (confidence: #{inj[:confidence]})", execution_id: exec.execution_id }
        end.first(3)
      end

      # --- Helpers ---

      def match_patterns(text, patterns, type)
        patterns.filter_map { |p| { type: type, pattern: p.source.truncate(80) } if text.match?(p) }
      end

      def compute_injection_confidence(matches, text)
        base = [matches.size * 0.3, 0.9].min
        base += matches.count { |m| m[:type] == "role_hijack" } * 0.15
        base += 0.1 if matches.map { |m| m[:type] }.uniq.size > 1
        base *= 0.85 if text.length > 5000
        [base, 1.0].min
      end

      def classify_risk(anomalies)
        return "low" if anomalies.empty?
        c = anomalies.count { |a| a[:severity] == "critical" }
        h = anomalies.count { |a| a[:severity] == "high" }
        return "critical" if c >= 2 || (c >= 1 && h >= 2)
        return "high" if c >= 1 || h >= 2
        return "medium" if h >= 1 || anomalies.size >= 2
        "low"
      end

      def compute_overall_risk(reports)
        return "low" if reports.empty?
        levels = reports.map { |r| r[:risk_level] }
        return "critical" if levels.include?("critical") || reports.any? { |r| r[:rogue_detected] }
        return "high" if levels.count("high") >= 2
        return "medium" if levels.count("high") >= 1 || levels.count("medium") >= 3
        "low"
      end

      def build_recommendations(anomalies, risk_level)
        map = {
          "excessive_tool_calls" => "Reduce tool call frequency or increase rate limit",
          "high_error_rate" => "Investigate recurring execution failures; consider pausing agent",
          "cost_spike" => "Review budget allocation; consider tightening cost limits",
          "excessive_spawn_depth" => "Limit agent delegation depth; review spawning policies",
          "excessive_concurrent_executions" => "Add concurrency limits to execution pipeline"
        }
        recs = anomalies.filter_map { |a| map[a[:type]] }.uniq
        recs.unshift("URGENT: Immediately review agent activity and consider suspension") if risk_level == "critical"
        recs
      end

      def aggregate_recommendations(reports)
        rogue = reports.count { |r| r[:rogue_detected] }
        anom = reports.count { |r| r[:anomalies].any? }
        recs = []
        recs << "#{rogue} rogue agent(s) detected - immediate review required" if rogue.positive?
        recs << "#{anom} agent(s) showing anomalous behavior" if anom.positive?
        recs << "All agents operating within normal parameters" if rogue.zero? && anom.zero?
        recs
      end

      # --- Audit logging ---

      def log_analysis_audit(agent, anomalies, risk_level)
        return unless Powernode::ExtensionRegistry.loaded?("business")

        Ai::ComplianceAuditEntry.log!(
          account: @account, action_type: "agent_anomaly_analysis",
          resource_type: "Ai::Agent", resource_id: agent.id,
          outcome: anomalies.any? ? "warning" : "success",
          description: "Anomaly analysis: risk=#{risk_level}, count=#{anomalies.size}",
          context: { risk_level: risk_level, anomaly_types: anomalies.map { |a| a[:type] }.uniq }
        )
      rescue StandardError => e
        Rails.logger.error "[AgentAnomalyDetection] log_analysis_audit: #{e.message}"
      end

      def log_policy_check(agent, policy, action_type, result)
        return unless Powernode::ExtensionRegistry.loaded?("business")

        Ai::ComplianceAuditEntry.log!(
          account: @account, action_type: "agent_policy_evaluation",
          resource_type: "Ai::Agent", resource_id: agent.id,
          outcome: result[:allowed] ? "warning" : "blocked",
          description: "Policy '#{policy.name}' for '#{action_type}': #{result[:reason]}",
          context: { policy_id: policy.id, enforcement: result[:enforcement] }
        )
      rescue StandardError => e
        Rails.logger.error "[AgentAnomalyDetection] log_policy_check: #{e.message}"
      end

      def record_injection_detection(matches, confidence, action_taken, text, context)
        if Powernode::ExtensionRegistry.loaded?("business")
          classification = Ai::DataClassification.where(account: @account).by_level("restricted").first
          if classification
            classification.record_detection!(
              source_type: context[:source_type] || "AgentInput",
              source_id: context[:source_id] || SecureRandom.uuid,
              field_path: context[:field_path], original: text.truncate(500),
              action: action_taken, confidence: confidence
            )
          end

          policy = Ai::CompliancePolicy.where(account: @account).active.by_type("output_filter").first
          if policy && confidence >= 0.6
            policy.record_violation!(
              source_type: context[:source_type] || "AgentInput",
              source_id: context[:source_id] || SecureRandom.uuid,
              description: "Prompt injection (confidence: #{confidence.round(4)}, patterns: #{matches.size})",
              context: { patterns: matches.map { |m| m[:type] }, confidence: confidence },
              severity: confidence >= 0.8 ? "critical" : "high"
            )
          end
        end
        Rails.logger.warn "[AgentAnomalyDetection] Injection: conf=#{confidence.round(4)}, patterns=#{matches.size}, action=#{action_taken}"
      rescue StandardError => e
        Rails.logger.error "[AgentAnomalyDetection] record_injection: #{e.message}"
      end

      def record_rogue_detection(agent, indicators, recommended_action)
        if Powernode::ExtensionRegistry.loaded?("business")
          policy = Ai::CompliancePolicy.where(account: @account).active.by_type("audit").first
          if policy
            policy.record_violation!(
              source_type: "Ai::Agent", source_id: agent.id,
              description: "Rogue behavior: #{indicators.size} indicator(s), action: #{recommended_action}",
              context: { indicators: indicators.map { |i| i.slice(:type, :severity) }, recommended_action: recommended_action },
              severity: indicators.any? { |i| i[:severity] == "critical" } ? "critical" : "high"
            )
          end
          Ai::ComplianceAuditEntry.log!(
            account: @account, action_type: "rogue_agent_detected",
            resource_type: "Ai::Agent", resource_id: agent.id, outcome: "blocked",
            description: "Rogue: #{indicators.size} indicators, action: #{recommended_action}",
            context: { indicators: indicators, recommended_action: recommended_action }
          )
        end
        Rails.logger.warn "[AgentAnomalyDetection] Rogue: agent=#{agent.id}, indicators=#{indicators.size}"
      rescue StandardError => e
        Rails.logger.error "[AgentAnomalyDetection] record_rogue: #{e.message}"
      end
    end
  end
end
