# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class GovernanceController < InternalBaseController
          # POST /api/v1/internal/ai/governance/scan_all
          # Called by AiGovernanceScanJob — scan all active agents for governance violations
          def scan_all
            total_reports = 0

            Account.active.find_each do |account|
              next if account.ai_suspended?

              service = ::Ai::Governance::MonitorService.new(account: account)

              account.ai_agents.where(status: "active").find_each do |agent|
                reports = service.scan_agent!(agent: agent)
                total_reports += reports.size
              rescue StandardError => e
                Rails.logger.error "[Governance] Scan failed for agent #{agent.id}: #{e.message}"
              end
            rescue StandardError => e
              Rails.logger.error "[Governance] Scan failed for account #{account.id}: #{e.message}"
            end

            render_success(reports_generated: total_reports)
          end

          # POST /api/v1/internal/ai/governance/detect_collusion
          # Called by AiCollusionDetectionJob — detect collusion patterns across accounts
          def detect_collusion
            total_indicators = 0

            Account.active.find_each do |account|
              next if account.ai_suspended?

              service = ::Ai::Governance::MonitorService.new(account: account)
              indicators = service.detect_collusion!
              total_indicators += indicators.size
            rescue StandardError => e
              Rails.logger.error "[Governance] Collusion detection failed for account #{account.id}: #{e.message}"
            end

            render_success(collusion_indicators: total_indicators)
          end
        end
      end
    end
  end
end
