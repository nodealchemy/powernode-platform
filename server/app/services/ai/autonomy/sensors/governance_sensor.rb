# frozen_string_literal: true

module Ai
  module Autonomy
    module Sensors
      class GovernanceSensor < Base
        def collect
          observations = []

          critical_reports = Ai::GovernanceReport.where(account: account)
            .open_reports.critical

          critical_reports.each do |report|
            observations << build_observation(
              sensor_type: "governance",
              observation_type: "alert",
              severity: "critical",
              title: "Critical governance report: #{report.report_type} for agent #{report.subject_agent_id}",
              data: {
                report_id: report.id,
                report_type: report.report_type,
                subject_agent_id: report.subject_agent_id,
                confidence: report.confidence_score,
                fingerprint: "governance_#{report.id}"
              },
              requires_action: true,
              expires_at: 4.hours.from_now
            )
          end

          collusion = Ai::CollusionIndicator.where(account: account)
            .high_confidence
            .where("created_at >= ?", 7.days.ago)

          if collusion.any?
            observations << build_observation(
              sensor_type: "governance",
              observation_type: "alert",
              severity: "warning",
              title: "#{collusion.count} high-confidence collusion indicators detected",
              data: {
                indicator_count: collusion.count,
                types: collusion.pluck(:indicator_type).tally,
                fingerprint: "collusion_#{collusion.count}"
              },
              requires_action: true,
              expires_at: 24.hours.from_now
            )
          end

          observations
        end
      end
    end
  end
end
