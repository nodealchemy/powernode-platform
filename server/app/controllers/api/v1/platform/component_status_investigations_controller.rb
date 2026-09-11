# frozen_string_literal: true

module Api
  module V1
    module Platform
      # THE DRAWER'S INVESTIGATION SURFACE (design §5.3 and §6, increment A9).
      #
      #   GET  :id/investigations   what has been investigated about this component
      #   POST :id/investigations   the operator's "Investigate" button
      #
      # ── TWO PERMISSIONS, NOT ONE ────────────────────────────────────────────
      # Reading is `platform.status.read`, the same floor that buys the picture
      # everywhere else on this plane. STARTING one is `ai.autonomy.manage`,
      # because it spends money (an LLM call) and creates a row somebody has to
      # dispose of. That is the identical split
      # `Ai::Tools::PlatformInvestigationTool` makes, deliberately: an operator
      # who can start an investigation from the drawer and not from MCP — or
      # the reverse — is a permission model with two answers to one question.
      #
      # Both are declared as `before_action`s rather than checked inside an
      # action body. A `render` from an action body does NOT halt the action in
      # Rails, so a guard written there emits a clean 403 and then runs the
      # mutation anyway.
      #
      # ── THE BOUNDS ARE THE SERVICE'S ────────────────────────────────────────
      # The open-fingerprint rule and the per-account daily cap live in
      # `Platform::InvestigationService` and are enforced there. This
      # controller re-implements neither. A cap re-checked here would be a
      # second, weaker cap in front of the real one, and the one an operator
      # could get around by using the MCP verb instead.
      #
      # ── IT OPENS; IT DOES NOT CONCLUDE ──────────────────────────────────────
      # Ranking is an LLM call against a canonical agent and runs in the worker
      # (`PlatformInvestigationJob`), never in this request thread. A 201
      # carrying an `open` investigation with evidence and no hypotheses is the
      # correct result of pressing the button.
      #
      # THE LEADING :: IS LOAD-BEARING: this class is lexically inside
      # `Api::V1::Platform`, so a bare `Platform::Investigation` resolves to
      # `Api::V1::Platform::Investigation` and raises NameError.
      class ComponentStatusInvestigationsController < ApplicationController
        include Paginatable
        include ::Platform::ComponentStatusScoped

        # How many concluded investigations the drawer shows beside the open
        # one. The drawer is a panel, not an audit log: an operator handed
        # fifty rows has been handed none, and the full history is a paginated
        # read somebody can add when a screen needs it.
        RECENT_LIMIT = 10

        before_action :validate_read_permission
        before_action :validate_write_permission, only: :create
        before_action :set_component_status

        # GET /api/v1/platform/component_statuses/:component_status_id/investigations
        def index
          scope = investigations_scope

          render_success(
            component_status_id: @component_status.id,
            scope: component_scope,
            open: scope.open_investigations.recent_first.map { |row| serialize(row, evidence: true) },
            recent: scope.concluded.recent_first.limit(RECENT_LIMIT).map { |row| serialize(row) },
            daily_cap: ::Platform::InvestigationService.daily_cap
          )
        end

        # POST /api/v1/platform/component_statuses/:component_status_id/investigations
        def create
          # THE CALLER'S ACCOUNT, NOT THE COMPONENT'S (A9 review S1). For a
          # SHARED component `@component_status.account` is nil, which filed the
          # investigation in a bucket every tenant shares — jointly capped,
          # visible to every tenant, and able to refuse them all with
          # AlreadyOpen. A user is known here, so the investigation is theirs;
          # the service keeps an account-scoped component's investigation on
          # that component's own account regardless. The automatic triggers
          # have no user and correctly keep the component's account.
          result = ::Platform::InvestigationService
                   .new(account: current_user.account)
                   .open!(@component_status, trigger: ::Platform::Investigation::TRIGGER_OPERATOR,
                                             opened_by: current_user)

          if result[:refused]
            # A REFUSAL IS NOT AN ERROR, and 409 rather than 422 says which:
            # the request was well-formed and the platform declined it because
            # of a state that will change. The reason is a token the drawer can
            # render a specific sentence for, and the cap travels with it so a
            # cap refusal can say what the cap is.
            return render_error(refusal_message(result[:refused]), status: :conflict,
                                details: { refused: result[:refused],
                                           daily_cap: ::Platform::InvestigationService.daily_cap })
          end

          render_success({ investigation: serialize(result[:investigation], evidence: true),
                           scope: component_scope },
                         status: :created)
        end

        private

        def validate_read_permission
          require_permission("platform.status.read")
        end

        def validate_write_permission
          require_permission("ai.autonomy.manage")
        end

        # This component's investigations, matched the way the plane matches a
        # component everywhere else: by (kind, ref) rather than by row id, so a
        # component that was reaped and re-created still shows its own history.
        # Account-scoped the same way the row is, shared rows included.
        # Unchanged in shape and now correct in effect: after S1 an operator-
        # opened investigation of a shared component carries the OPENER's
        # account, so `[current, nil]` shows a tenant its own investigations
        # plus the genuinely shared ones an automatic trigger opened — and no
        # longer another tenant's.
        def investigations_scope
          ::Platform::Investigation
            .where(account_id: [ current_user.account.id, nil ])
            .for_component(@component_status.component_kind, @component_status.component_ref)
        end

        def refusal_message(reason)
          case reason
          when ::Platform::InvestigationService::REFUSED_ALREADY_OPEN
            "An investigation of this component is already open"
          when ::Platform::InvestigationService::REFUSED_DAILY_CAP
            "This account has reached its daily investigation cap"
          else
            "Investigation refused: #{reason}"
          end
        end

        # ONE SHAPE for an investigation, shared by both actions. `confidence`
        # is whatever core computed and carries its STATE alongside the number,
        # because `not_measured` (the evidence set was empty) is not the same
        # answer as a confidence of 0 and a bare float cannot say which.
        def serialize(investigation, evidence: false)
          base = {
            id: investigation.id,
            component_kind: investigation.component_kind,
            component_ref: investigation.component_ref,
            trigger: investigation.trigger,
            status: investigation.status,
            open: investigation.open?,
            hypotheses: Array(investigation.hypotheses),
            conclusion: investigation.conclusion,
            agent_id: investigation.agent_id,
            # nil when an automatic trigger opened it (G1).
            opened_by_user_id: investigation.opened_by_user_id,
            # Why no agent ranked it, or nil when one did. On the concluded
            # rows too, which carry no evidence: that is where an operator
            # reads "ranking was not run".
            ranking: investigation.ranking_record,
            started_at: investigation.started_at&.utc&.iso8601,
            completed_at: investigation.completed_at&.utc&.iso8601
          }

          evidence ? base.merge(evidence: investigation.evidence || {}) : base
        end
      end
    end
  end
end
