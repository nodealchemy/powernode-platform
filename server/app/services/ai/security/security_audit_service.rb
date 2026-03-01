# frozen_string_literal: true

module Ai
  module Security
    class SecurityAuditService
      # Comprehensive security audit logging, compliance matrix (ASI01-ASI10),
      # risk scoring, and reporting.

      ASI_REFERENCES = {
        "ASI01" => { name: "Excessive Agency", description: "Agents granted more authority than needed" },
        "ASI02" => { name: "Prompt Injection", description: "Manipulation of agent instructions via crafted inputs" },
        "ASI03" => { name: "Insufficient Identity", description: "Weak or missing agent identity management" },
        "ASI04" => { name: "Data Governance", description: "Improper handling of sensitive data by agents" },
        "ASI05" => { name: "Least Privilege", description: "Failure to enforce minimum necessary permissions" },
        "ASI06" => { name: "Inadequate Sandboxing", description: "Insufficient isolation of agent execution environments" },
        "ASI07" => { name: "Insecure Communication", description: "Unprotected inter-agent or agent-system communication" },
        "ASI08" => { name: "Rogue Agent", description: "Agents operating outside defined behavioral boundaries" },
        "ASI09" => { name: "Supply Chain Risk", description: "Vulnerabilities in agent dependencies and integrations" },
        "ASI10" => { name: "Logging & Monitoring", description: "Insufficient security event logging and monitoring" }
      }.freeze

      CSA_PILLARS = {
        "identity" => { services: %w[AgentIdentityService], asi_refs: %w[ASI03] },
        "behavior" => { services: %w[PrivilegeEnforcementService AgentAnomalyDetectionService], asi_refs: %w[ASI01 ASI05 ASI08] },
        "data_governance" => { services: %w[PiiRedactionService], asi_refs: %w[ASI04 ASI09] },
        "segmentation" => { services: %w[EncryptedCommunicationService], asi_refs: %w[ASI06 ASI07] },
        "incident_response" => { services: %w[QuarantineService], asi_refs: %w[ASI08 ASI10] }
      }.freeze

      def initialize(account:)
        @account = account
      end

      # Log a security audit event.
      def log!(action:, outcome:, asi_reference: nil, agent: nil, user: nil,
               context: {}, severity: "info", details: {})
        Ai::SecurityAuditTrail.log!(
          action: action,
          outcome: outcome,
          account: @account,
          agent_id: agent&.id,
          user_id: user&.id,
          asi_reference: asi_reference,
          source_service: "SecurityAuditService",
          severity: severity,
          context: context,
          details: details
        )
      end

      # Build a compliance matrix showing coverage for each ASI reference (ASI01-ASI10).
      # Returns an array of 10 items with coverage score, status, and details.
      def compliance_matrix(account: nil)
        target_account = account || @account
        period = 30.days

        ASI_REFERENCES.map do |ref, info|
          trails = Ai::SecurityAuditTrail.where(account: target_account)
            .by_asi(ref)
            .recent(period)

          total_events = trails.count
          denied_events = trails.by_outcome("denied").count + trails.by_outcome("blocked").count
          allowed_events = trails.by_outcome("allowed").count

          coverage = compute_coverage_score(ref, total_events, denied_events, allowed_events)
          status = coverage_status(coverage)

          {
            asi_reference: ref,
            name: info[:name],
            description: info[:description],
            coverage_score: coverage.round(4),
            status: status,
            total_events: total_events,
            denied_events: denied_events,
            allowed_events: allowed_events,
            last_event_at: trails.order(created_at: :desc).first&.created_at&.iso8601
          }
        end
      end

      # Compute a composite risk score for a given agent.
      def risk_score(agent:)
        period = 30.days

        # Factor 1: Anomaly history
        anomaly_trails = Ai::SecurityAuditTrail.for_agent(agent.id)
          .by_action("agent_anomaly_analysis")
          .recent(period)
        anomaly_count = anomaly_trails.count
        anomaly_factor = [anomaly_count.to_f / 20.0, 1.0].min

        # Factor 2: Privilege violations (denied/blocked actions)
        violations = Ai::SecurityAuditTrail.for_agent(agent.id)
          .denied_or_blocked
          .recent(period)
          .count
        violation_factor = [violations.to_f / 10.0, 1.0].min

        # Factor 3: Quarantine history
        quarantines = Ai::QuarantineRecord.for_agent(agent.id)
          .where(account: @account)
          .recent(period)
        quarantine_count = quarantines.count
        critical_quarantines = quarantines.critical.count
        quarantine_factor = [
          (quarantine_count.to_f / 5.0) + (critical_quarantines.to_f / 2.0),
          1.0
        ].min

        # Factor 4: Communication patterns (blocked comms)
        blocked_comms = Ai::SecurityAuditTrail.for_agent(agent.id)
          .by_asi("ASI07")
          .by_outcome("denied")
          .recent(period)
          .count
        comm_factor = [blocked_comms.to_f / 5.0, 1.0].min

        # Weighted composite
        composite = (
          anomaly_factor * 0.25 +
          violation_factor * 0.30 +
          quarantine_factor * 0.30 +
          comm_factor * 0.15
        ).round(4)

        {
          agent_id: agent.id,
          composite_score: composite,
          factors: {
            anomaly: anomaly_factor.round(4),
            violations: violation_factor.round(4),
            quarantine: quarantine_factor.round(4),
            communication: comm_factor.round(4)
          },
          risk_level: risk_level(composite),
          period_days: 30
        }
      end

      # Filtered audit trail events.
      def recent_events(account: nil, filters: {})
        target_account = account || @account
        scope = Ai::SecurityAuditTrail.where(account: target_account)

        scope = scope.for_agent(filters[:agent_id]) if filters[:agent_id]
        scope = scope.by_asi(filters[:asi_reference]) if filters[:asi_reference]
        scope = scope.by_outcome(filters[:outcome]) if filters[:outcome]
        scope = scope.by_severity(filters[:severity]) if filters[:severity]
        scope = scope.by_action(filters[:action]) if filters[:action]
        scope = scope.by_source(filters[:source_service]) if filters[:source_service]

        if filters[:since]
          scope = scope.where("ai_security_audit_trails.created_at >= ?", filters[:since])
        end

        scope.order(created_at: :desc)
      end

      # Aggregate security report for an account over a given period.
      def security_report(account: nil, period: 30.days)
        target_account = account || @account

        trails = Ai::SecurityAuditTrail.where(account: target_account).recent(period)

        total = trails.count
        by_outcome = trails.group(:outcome).count
        by_severity = trails.group(:severity).count
        by_asi = trails.group(:asi_reference).count

        # Top risk agents
        top_agents = trails.denied_or_blocked
          .where.not(agent_id: nil)
          .group(:agent_id)
          .count
          .sort_by { |_, v| -v }
          .first(10)
          .map { |agent_id, count| { agent_id: agent_id, violation_count: count } }

        # Active quarantines
        active_quarantines = Ai::QuarantineRecord.where(account: target_account).active.count

        # Compliance summary
        matrix = compliance_matrix(account: target_account)
        avg_coverage = matrix.sum { |m| m[:coverage_score] } / matrix.size.to_f

        recommendations = build_recommendations(by_outcome, active_quarantines, avg_coverage, top_agents)

        {
          account_id: target_account.id,
          period_days: (period / 1.day).to_i,
          generated_at: Time.current.iso8601,
          total_events: total,
          by_outcome: by_outcome,
          by_severity: by_severity,
          by_asi_reference: by_asi,
          top_risk_agents: top_agents,
          active_quarantines: active_quarantines,
          average_compliance_coverage: avg_coverage.round(4),
          recommendations: recommendations
        }
      end

      private

      def compute_coverage_score(asi_ref, total_events, denied_events, allowed_events)
        # Base coverage from having events at all
        return 0.0 if total_events.zero?

        event_score = [total_events.to_f / 50.0, 0.5].min

        # Enforcement ratio
        enforcement_ratio = if (denied_events + allowed_events).positive?
                              1.0 - (denied_events.to_f / (denied_events + allowed_events))
                            else
                              0.5
                            end

        (event_score + enforcement_ratio * 0.5).round(4)
      end

      def coverage_status(score)
        if score >= 0.8
          "good"
        elsif score >= 0.5
          "moderate"
        elsif score > 0.0
          "needs_improvement"
        else
          "no_coverage"
        end
      end

      def risk_level(score)
        if score >= 0.8
          "critical"
        elsif score >= 0.6
          "high"
        elsif score >= 0.3
          "medium"
        else
          "low"
        end
      end

      def build_recommendations(by_outcome, active_quarantines, avg_coverage, top_agents)
        recs = []

        blocked = (by_outcome["blocked"] || 0) + (by_outcome["denied"] || 0)
        recs << "High volume of blocked/denied actions (#{blocked}) - review agent policies" if blocked > 20
        recs << "#{active_quarantines} agent(s) currently quarantined - review for restoration" if active_quarantines.positive?
        recs << "Average compliance coverage is #{(avg_coverage * 100).round(1)}% - consider enabling more ASI protections" if avg_coverage < 0.5
        recs << "#{top_agents.size} agents with violations - prioritize review of top risk agents" if top_agents.size > 3
        recs << "Security posture is healthy - continue monitoring" if recs.empty?

        recs
      end
    end
  end
end
