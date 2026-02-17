# frozen_string_literal: true

module Ai
  module CodeFactory
    class HarnessGapService
      class GapError < StandardError; end

      DEFAULT_SLA_HOURS = 72

      def initialize(account:)
        @account = account
        @logger = Rails.logger
      end

      # Create a harness gap from an incident
      def create_from_incident(incident_id:, description:, severity: "medium",
                               incident_source: "review_finding", risk_contract: nil,
                               sla_hours: DEFAULT_SLA_HOURS)
        gap = @account.ai_code_factory_harness_gaps.create!(
          incident_source: incident_source,
          incident_id: incident_id,
          description: description,
          severity: severity,
          risk_contract: risk_contract,
          sla_deadline: sla_hours.hours.from_now
        )

        @logger.info("[CodeFactory::HarnessGap] Created gap #{gap.id} for incident #{incident_id}")
        gap
      rescue StandardError => e
        @logger.error("[CodeFactory::HarnessGap] Error creating gap: #{e.message}")
        raise GapError, e.message
      end

      # Add a test case reference to a harness gap
      def add_test_case(harness_gap:, test_reference:)
        harness_gap.add_test_case!(test_reference)

        # Extract learning from the gap closure
        extract_gap_learning(harness_gap)

        @logger.info("[CodeFactory::HarnessGap] Test case added to gap #{harness_gap.id}: #{test_reference}")
        harness_gap
      end

      # Check SLA compliance across all open gaps
      def check_sla_compliance
        past_sla = @account.ai_code_factory_harness_gaps.past_sla

        {
          total_open: @account.ai_code_factory_harness_gaps.open_gaps.count,
          past_sla_count: past_sla.count,
          past_sla_gaps: past_sla.map do |gap|
            {
              id: gap.id,
              incident_id: gap.incident_id,
              severity: gap.severity,
              sla_deadline: gap.sla_deadline,
              hours_overdue: ((Time.current - gap.sla_deadline) / 1.hour).round(1)
            }
          end
        }
      end

      # Get metrics for harness gaps
      def metrics
        gaps = @account.ai_code_factory_harness_gaps

        {
          total: gaps.count,
          open: gaps.open_gaps.count,
          in_progress: gaps.in_progress.count,
          closed: gaps.where(status: "closed").count,
          sla_compliance_rate: calculate_sla_compliance_rate(gaps),
          by_severity: {
            critical: gaps.by_severity("critical").count,
            high: gaps.by_severity("high").count,
            medium: gaps.by_severity("medium").count,
            low: gaps.by_severity("low").count
          }
        }
      end

      private

      def calculate_sla_compliance_rate(gaps)
        closed = gaps.where(status: "closed").where.not(sla_met: nil)
        return 100.0 if closed.count.zero?

        met = closed.where(sla_met: true).count
        (met.to_f / closed.count * 100).round(1)
      end

      def extract_gap_learning(gap)
        return unless defined?(Ai::Learning::CompoundLearningService)

        Ai::Learning::CompoundLearningService.new(account: @account).extract_from_event(
          event_type: "harness_gap_closed",
          context: {
            incident_id: gap.incident_id,
            incident_source: gap.incident_source,
            severity: gap.severity,
            test_reference: gap.test_case_reference,
            sla_met: gap.sla_met
          }
        )
      rescue StandardError => e
        @logger.warn("[CodeFactory::HarnessGap] Learning extraction failed: #{e.message}")
      end
    end
  end
end
