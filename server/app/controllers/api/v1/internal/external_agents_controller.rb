# frozen_string_literal: true

module Api
  module V1
    module Internal
      # Receives the raw outcome of an external A2A agent-card fetch from the
      # standalone worker (ExternalAgentCardFetchJob). The worker does only the
      # network I/O; this endpoint performs the A2A parse/validate/persist so all
      # model/DB access stays on the server (worker is API-only).
      #
      # Worker-receiver discipline: this is a worker callback, so it MUST NOT
      # return 5xx on a processing error (a 500 would trigger Sidekiq retry
      # storms). On any error it logs and returns 2xx. It is idempotent — it
      # simply applies the latest reported outcome.
      class ExternalAgentsController < InternalBaseController
        # POST /api/v1/internal/external_agents/:id/card_result
        #
        # Accepts two shapes:
        #   success: { http_status:, body: <raw response body string> }
        #   failure: { error: <string> }
        def card_result
          agent = ExternalAgent.find_by(id: params[:id])

          # Agent deleted between enqueue and callback — idempotent no-op, 2xx so
          # the worker doesn't retry a job that can never succeed.
          unless agent
            Rails.logger.warn("[Internal::ExternalAgents#card_result] Agent #{params[:id]} not found, skipping")
            return render_success(applied: false, reason: "agent_not_found")
          end

          if params[:error].present?
            agent.apply_card_result(success: false, error: params[:error].to_s)
            return render_success(applied: true, outcome: "failed", health_status: agent.health_status)
          end

          parsed = A2a::Client::AgentDiscovery.parse_card(params[:body])

          if parsed[:success]
            agent.apply_card_result(success: true, card: parsed[:card])
            render_success(applied: true, outcome: "success", health_status: agent.health_status)
          else
            agent.apply_card_result(success: false, error: parsed[:error])
            render_success(applied: true, outcome: "failed", health_status: agent.health_status)
          end
        rescue StandardError => e
          # Never 500 on a worker callback — log and ack so the provider/worker
          # does not enter a retry storm.
          Rails.logger.error("[Internal::ExternalAgents#card_result] Failed for #{params[:id]}: #{e.message}")
          render_success(applied: false, error: e.message)
        end
      end
    end
  end
end
