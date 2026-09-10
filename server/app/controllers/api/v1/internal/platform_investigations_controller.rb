# frozen_string_literal: true

module Api
  module V1
    module Internal
      # The worker→server door for INVESTIGATION RANKING (design §5.3, A6).
      #
      # `Platform::InvestigationService#open!` records the evidence and stops.
      # Ranking asks a canonical agent to read that evidence, which is an LLM
      # call — seconds to minutes, a cost, and a failure mode (a provider
      # outage) unrelated to whatever opened the investigation. The server runs
      # no Sidekiq, so the RETRY lives in the worker
      # (`PlatformInvestigationJob`) and the WORK lives here: the same split
      # `PlatformStatusController` uses for the sweep, and for the same reason
      # — the server owns every gate, so the worker can call in unconditionally.
      #
      # THE LEADING :: IS LOAD-BEARING. This class is lexically inside
      # `Api::V1::Internal`, and `Api::V1::Platform` exists (the component
      # status REST surface), so a bare `Platform::Investigation` resolves to
      # `Api::V1::Platform::Investigation` and raises NameError — which the
      # rescue below would then report as a 500 for every investigation on the
      # platform. Same trap `PlatformStatusController` documents.
      #
      # ── TENANCY IS THE WORKER'S CERTIFICATE, NOT A PARAMETER ────────────────
      # `InternalBaseController` resolves the calling worker from the mTLS CN
      # and sets `@current_account` from it. The lookup is anchored on that,
      # never on an account id in the request body: a body parameter is a value
      # the caller chooses, and an internal door that takes one is an internal
      # door with no tenancy at all. Shared (NULL-account) investigations are
      # included for the same reason the MCP tool includes them — a
      # process-wide component has no tenant and would otherwise be
      # unreachable.
      class PlatformInvestigationsController < InternalBaseController
        # POST /api/v1/internal/platform/investigations/:id/conclude
        #
        # Ranks one open investigation and concludes it. Idempotent by way of
        # the model: an investigation that already concluded is returned
        # unchanged rather than re-ranked, so a worker retry after a timeout
        # that actually succeeded does not spend a second LLM call.
        def conclude
          investigation = find_investigation
          return render_error("Investigation not found", status: :not_found) if investigation.nil?

          if investigation.concluded?
            return render_success(investigation: serialize(investigation), ranked: false,
                                  reason: "already_concluded")
          end

          ranking = ::Platform::Investigation::Ranking.run!(investigation, account: @current_account)

          if ranking[:error].present?
            record_ranking_error(investigation, ranking[:error])
            return render_error("Ranking failed: #{ranking[:error]}", status: :unprocessable_content)
          end

          concluded = service_for(investigation).conclude!(
            investigation, ranked: ranking[:ranked], agent: ranking[:agent]
          )

          render_success(investigation: serialize(concluded), ranked: true,
                         agent_id: ranking[:agent]&.id)
        rescue StandardError => e
          Rails.logger.error("[PlatformInvestigations] conclude failed for #{params[:id]}: " \
                             "#{e.class}: #{e.message}")
          render_error("Investigation could not be concluded: #{e.message}", status: :internal_server_error)
        end

        private

        # Anchored on the worker's own account. A foreign-account id is NOT
        # FOUND rather than forbidden: an internal door that distinguishes the
        # two tells a caller which ids exist.
        def find_investigation
          ::Platform::Investigation
            .where(account_id: [ @current_account&.id, nil ].uniq)
            .find_by(id: params[:id])
        end

        # An investigation belonging to a different account than the worker's
        # is unreachable above, so the service is always built on the row's own
        # account — never on the worker's, which would silently write the
        # learning and the remediation offer into the wrong tenant.
        def service_for(investigation)
          ::Platform::InvestigationService.new(account: investigation.account)
        end

        # The investigation stays OPEN and the reason is recorded, so a
        # retryable failure is retried rather than concluded away. `evidence`
        # already carries an `errors` map by contract (an evidence source that
        # raised lands there too), which is the honest home for "this class of
        # information could not be obtained" — no column, no migration, and it
        # renders in the same place an operator already reads about gaps.
        def record_ranking_error(investigation, message)
          evidence = investigation.evidence.is_a?(Hash) ? investigation.evidence.deep_dup : {}
          errors = evidence["errors"].is_a?(Hash) ? evidence["errors"] : {}
          evidence["errors"] = errors.merge("ranking" => message.to_s.truncate(500))

          investigation.update_columns(evidence: evidence, updated_at: Time.current)
        rescue StandardError => e
          Rails.logger.error("[PlatformInvestigations] could not record ranking error: #{e.class}: #{e.message}")
        end

        def serialize(investigation)
          {
            id: investigation.id,
            component_kind: investigation.component_kind,
            component_ref: investigation.component_ref,
            status: investigation.status,
            trigger: investigation.trigger,
            hypotheses: investigation.hypotheses,
            conclusion: investigation.conclusion,
            agent_id: investigation.agent_id,
            completed_at: investigation.completed_at
          }
        end
      end
    end
  end
end
