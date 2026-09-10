# frozen_string_literal: true

module Platform
  module Status
    # The READ side of the status plane: one place that turns request or MCP
    # params into a scope of Platform::ComponentStatus rows, so the REST door
    # and the MCP tool cannot answer the same question differently.
    #
    # ── THE THREE-VALUED ENVIRONMENT FILTER (design §4.6) ───────────────────
    #
    # Most core kinds carry NO environment: an AI provider, a circuit breaker
    # and the platform's own subsystems are not "in dev" or "in prod". So a
    # plane filter has three cases, not two:
    #
    #   environment absent      → every row (in-plane, plane-less, all planes)
    #   environment = "none"    → plane-less rows ONLY
    #   environment = <id|slug> → that plane's rows PLUS the plane-less ones,
    #                             and NEVER another plane's
    #
    # The third case is the one a `where(environment_id: x)` gets wrong by
    # dropping the plane-less rows, and a `where.not(environment_id: y)` gets
    # wrong by showing another plane's. Every row therefore carries a `plane`
    # label — "in" or "none" — so the operator can see WHICH half of a
    # filtered list a card came from rather than inferring it.
    #
    # ── SHARED ROWS ─────────────────────────────────────────────────────────
    #
    # A process-wide contributor (`account_scoped? == false`) writes a row with
    # a NULL account. Those rows belong to every tenant's view — they render in
    # a "shared infrastructure" section — so the base scope is
    # `account_id IN (this account, NULL)`, matching what
    # Platform::Status::Rollup.neighbourhood_for already loads.
    class Query
      # Rows come back worst-first: an operator opening page 1 of a 150-row
      # plane wants the outages, not the alphabet. Ties break on kind then ref
      # so the order is TOTAL — a non-deterministic tail makes page 2 lie.
      ORDER_SQL = <<~SQL.squish.freeze
        CASE platform_component_statuses.verdict
          WHEN 'down' THEN 0
          WHEN 'degraded' THEN 1
          WHEN 'not_measured' THEN 2
          WHEN 'progressing' THEN 3
          WHEN 'held' THEN 4
          ELSE 5
        END,
        platform_component_statuses.component_kind ASC,
        platform_component_statuses.component_ref ASC
      SQL

      # The value of `environment` that asks for the plane-less rows alone.
      NO_PLANE = "none"

      PLANE_IN   = "in"
      PLANE_NONE = "none"

      attr_reader :account, :kind, :verdict, :environment_param

      # @param account [Account] the tenant whose plane is being read
      # @param kind [String, nil] component_kind filter
      # @param verdict [String, nil] verdict filter (one of ComponentStatus::VERDICTS)
      # @param environment [String, nil] environment id, slug, or NO_PLANE
      def initialize(account:, kind: nil, verdict: nil, environment: nil)
        @account = account
        @kind = kind.presence&.to_s
        @verdict = verdict.presence&.to_s
        @environment_param = environment.presence&.to_s
      end

      # @return [ActiveRecord::Relation]
      def rows
        scope = ComponentStatus.where(account_id: [ account.id, nil ])
        scope = scope.for_kind(kind) if kind
        scope = scope.with_verdict(verdict) if verdict?
        scope = apply_environment(scope)
        scope.order(Arel.sql(ORDER_SQL))
      end

      # Is the requested verdict a real one? An unknown verdict must filter to
      # NOTHING rather than being silently ignored, which would answer a
      # question nobody asked with a full list.
      def verdict?
        verdict.present?
      end

      def known_verdict?
        verdict.nil? || ComponentStatus::VERDICTS.include?(verdict)
      end

      # nil when no plane was named or NO_PLANE was; otherwise the resolved
      # Ai::Environment. Memoized including the nil, so a slug that resolves to
      # nothing is looked up once.
      def environment
        return @environment if defined?(@environment)

        @environment = resolve_environment
      end

      # Did the caller name a plane that this account does not have? Answered
      # separately from `environment` being nil, because "no filter" and "a
      # filter naming nothing" are different answers and only one is an error.
      def unknown_environment?
        filtering_by_plane? && environment.nil?
      end

      def filtering_by_plane?
        environment_param.present? && environment_param != NO_PLANE
      end

      def plane_less_only?
        environment_param == NO_PLANE
      end

      # Which half of a plane-filtered list this row came from. "in" when the
      # row sits in the named plane; "none" when it is plane-less and rides
      # along. Unfiltered lists label the same way, so a card's plane is
      # readable without knowing what filter produced it.
      def self.plane_label(row)
        row.environment_id.nil? ? PLANE_NONE : PLANE_IN
      end

      # The filter as the response should echo it back, so a client can tell
      # an empty page under `environment=ci` from an empty page overall.
      def applied_filters
        {
          kind: kind,
          verdict: verdict,
          environment: environment_param,
          environment_id: environment&.id
        }.compact
      end

      private

      def apply_environment(scope)
        return scope.plane_less if plane_less_only?
        return scope unless filtering_by_plane?
        # A plane the account does not have selects nothing at all — NOT the
        # plane-less rows, which would answer a wrong question with a
        # plausible-looking list.
        return scope.none if environment.nil?

        scope.where(environment_id: [ environment.id, nil ])
      end

      def resolve_environment
        return nil unless filtering_by_plane?

        ::Ai::Environment.find_for_account(account.id, environment_param)
      end
    end
  end
end
