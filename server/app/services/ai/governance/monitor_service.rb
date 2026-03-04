# frozen_string_literal: true

module Ai
  module Governance
    class MonitorService
      COLLUSION_THRESHOLD = 0.7

      def initialize(account:)
        @account = account
      end

      def scan_agent!(agent:, monitor: nil)
        reports = []

        violations = check_policy_compliance(agent)
        violations.each do |violation|
          reports << create_report(
            monitor: monitor, subject_agent: agent,
            report_type: "policy_violation", severity: violation[:severity],
            evidence: violation, confidence: 0.9
          )
        end

        if resource_abuse?(agent)
          reports << create_report(
            monitor: monitor, subject_agent: agent,
            report_type: "resource_abuse", severity: "warning",
            evidence: { type: "excessive_resource_usage", agent_id: agent.id },
            confidence: 0.7
          )
        end

        anomaly = check_behavioral_anomaly(agent)
        if anomaly
          reports << create_report(
            monitor: monitor, subject_agent: agent,
            report_type: "anomaly", severity: anomaly[:severity],
            evidence: anomaly, confidence: anomaly[:confidence]
          )
        end

        reports
      end

      def scan_team!(team:, monitor: nil)
        reports = []

        members = team.members.includes(:agent)
        if members.size > 1
          exec_counts = members.map do |m|
            count = Ai::AgentExecution.where(ai_agent_id: m.ai_agent_id)
              .where("created_at >= ?", 7.days.ago).count
            { agent_id: m.ai_agent_id, count: count }
          end

          total = exec_counts.sum { |e| e[:count] }
          if total > 0
            max_share = exec_counts.max_by { |e| e[:count] }[:count].to_f / total
            if max_share > 0.8
              reports << create_report(
                monitor: monitor, subject_team: team,
                report_type: "anomaly", severity: "warning",
                evidence: { type: "unbalanced_contribution", distribution: exec_counts },
                confidence: 0.6
              )
            end
          end
        end

        reports
      end

      def detect_collusion!(scope: nil)
        indicators = []
        agents = Ai::Agent.where(account: @account, status: "active")

        agent_ids = agents.pluck(:id)
        agent_ids.combination(2).each do |a_id, b_id|
          score = collusion_score(a_id, b_id)
          next if score < COLLUSION_THRESHOLD

          indicator = Ai::CollusionIndicator.create!(
            account: @account,
            indicator_type: determine_collusion_type(a_id, b_id),
            agent_cluster: [a_id, b_id],
            correlation_score: score,
            evidence_summary: { pair: [a_id, b_id], score: score }
          )
          indicators << indicator

          create_report(
            subject_agent: Ai::Agent.find(a_id),
            report_type: "collusion_suspicion",
            severity: score >= 0.9 ? "critical" : "warning",
            evidence: { indicator_id: indicator.id, correlation_score: score, paired_with: b_id },
            confidence: score
          )
        end

        indicators
      end

      def auto_remediate!(report:)
        case report.report_type
        when "policy_violation"
          agent = report.subject_agent
          trust = Ai::AgentTrustScore.find_by(agent_id: agent&.id)
          if trust
            trust.update!(tier: "supervised", overall_score: [trust.overall_score - 0.2, 0.0].max)
            report.update!(auto_remediated: true)
          end
        when "resource_abuse"
          agent = report.subject_agent
          budget = Ai::AgentBudget.where(agent_id: agent&.id).active.first
          if budget
            budget.update!(allocated_cents: (budget.allocated_cents * 0.5).to_i)
            report.update!(auto_remediated: true)
          end
        when "collusion_suspicion"
          report.update!(status: "investigating")
        when "safety_concern"
          agent = report.subject_agent
          agent&.update!(status: "paused")
          report.update!(auto_remediated: true)
        end

        report.resolve!(status: "remediated") if report.auto_remediated?
      end

      private

      def check_policy_compliance(agent)
        violations = []

        daily_execs = Ai::AgentExecution.where(ai_agent_id: agent.id)
          .where("created_at >= ?", 24.hours.ago)
        daily_cost = daily_execs.sum(:cost_usd)

        if daily_cost > 10.0
          violations << { severity: "warning", type: "daily_cost_exceeded", cost: daily_cost.to_f, threshold: 10.0 }
        end

        total = daily_execs.count
        failed = daily_execs.where(status: "failed").count
        if total >= 10 && (failed.to_f / total) > 0.5
          violations << { severity: "warning", type: "high_error_rate", rate: (failed.to_f / total).round(2), total: total }
        end

        violations
      end

      def resource_abuse?(agent)
        daily_tokens = Ai::AgentExecution.where(ai_agent_id: agent.id)
          .where("created_at >= ?", 24.hours.ago)
          .sum(:tokens_used)

        daily_tokens > 1_000_000
      end

      def check_behavioral_anomaly(agent)
        recent_execs = Ai::AgentExecution.where(ai_agent_id: agent.id)
          .where("created_at >= ?", 24.hours.ago)

        hourly_counts = recent_execs.group_by_hour(:created_at).count rescue {}
        return nil if hourly_counts.size < 3

        avg = hourly_counts.values.sum.to_f / hourly_counts.size
        max = hourly_counts.values.max
        stddev = Math.sqrt(hourly_counts.values.sum { |v| (v - avg)**2 } / hourly_counts.size)

        return nil if stddev.zero?

        z_score = (max - avg) / stddev
        if z_score > 3.0
          {
            severity: "warning",
            type: "execution_spike",
            z_score: z_score.round(2),
            max_hourly: max,
            avg_hourly: avg.round(1),
            confidence: [z_score / 5.0, 0.95].min.round(2)
          }
        end
      end

      def collusion_score(agent_a_id, agent_b_id)
        a_reviews_b = Ai::AgentReview.where(reviewer_id: agent_a_id, reviewed_agent_id: agent_b_id).where(outcome: "approved").count rescue 0
        b_reviews_a = Ai::AgentReview.where(reviewer_id: agent_b_id, reviewed_agent_id: agent_a_id).where(outcome: "approved").count rescue 0
        total_reviews = (a_reviews_b + b_reviews_a).to_f
        reciprocity = total_reviews > 0 ? [total_reviews / 20.0, 1.0].min : 0.0

        trust_a = Ai::AgentTrustScore.find_by(agent_id: agent_a_id)&.overall_score || 0
        trust_b = Ai::AgentTrustScore.find_by(agent_id: agent_b_id)&.overall_score || 0
        trust_coupling = 1.0 - (trust_a - trust_b).abs

        (0.3 * reciprocity + 0.3 * trust_coupling + 0.4 * 0.0).round(4) # output_similarity TBD
      end

      def determine_collusion_type(_a_id, _b_id)
        "mutual_approval"
      end

      def create_report(monitor: nil, subject_agent: nil, subject_team: nil, report_type:, severity:, evidence:, confidence: 0.5)
        Ai::GovernanceReport.create!(
          account: @account,
          monitor_agent: monitor,
          subject_agent: subject_agent,
          subject_team: subject_team,
          report_type: report_type,
          severity: severity,
          evidence: evidence,
          confidence_score: confidence,
          recommended_actions: generate_recommendations(report_type, severity)
        )
      end

      def generate_recommendations(report_type, severity)
        case report_type
        when "policy_violation"
          ["Review agent configuration", severity == "critical" ? "Consider suspension" : "Monitor closely"]
        when "resource_abuse"
          ["Reduce budget allocation", "Review execution patterns"]
        when "collusion_suspicion"
          ["Separate agent assignments", "Reset peer trust signals", "Investigate output similarity"]
        when "anomaly"
          ["Review recent execution logs", "Check for configuration changes"]
        when "safety_concern"
          ["Quarantine agent immediately", "Review all recent outputs"]
        else
          ["Review and investigate"]
        end
      end
    end
  end
end
