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

          # THE INVESTIGATION'S OWN ACCOUNT, NEVER THE WORKER'S (A6
          # re-verification G3 + §4). There is one system worker platform-wide
          # and it concludes every tenant's investigation, so `@current_account`
          # is the WORKER's account, not the tenant's. Passing it here minted
          # the ranking clone in the worker's account and booked the spend
          # there: the tenant's evidence sent to another account's agent, and a
          # mis-billed ledger. The same rule `service_for` follows below.
          #
          # For a SHARED investigation opened by an automatic trigger the
          # account is nil, so no principal is minted and the investigation
          # concludes on core's deterministic candidates — the arm the spec now
          # proves THROUGH this door, rather than by calling `agent_for` with a
          # nil no caller passes.
          ranking = ::Platform::Investigation::Ranking.run!(investigation, account: investigation.account)

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

        # THE SYSTEM WORKER IS CROSS-ACCOUNT; AN ACCOUNT WORKER IS NOT.
        #
        # `Worker` enforces exactly ONE system worker globally
        # (`only_one_system_worker_globally`), and it belongs to a single
        # account. That worker runs `PlatformInvestigationJob` for every tenant.
        # Anchoring it on `[its own account, nil]` — as this door originally did
        # — meant every other tenant's investigation was NOT FOUND here, the job
        # raised, Sidekiq retried, and the investigation stayed open forever:
        # the same one-investigation-per-component-ever failure the A6 review
        # traced to F1–F3, reintroduced one layer further along. The request
        # spec could not see it because it created the worker in the
        # investigation's own account.
        #
        # So a system worker may conclude any account's investigation — the same
        # trust every other internal door extends to it (e.g.
        # `Internal::Ai::AgentExecutionsController` finds by id alone), and the
        # mTLS certificate is what establishes it. An ACCOUNT worker stays
        # anchored to its own account plus shared rows, and a foreign id is NOT
        # FOUND rather than forbidden, so it learns nothing about what exists
        # elsewhere.
        def find_investigation
          scope = ::Platform::Investigation
          scope = scope.where(account_id: [ @current_account&.id, nil ].uniq) unless @current_worker&.system?
          scope.find_by(id: params[:id])
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
