# frozen_string_literal: true

module Api
  module V1
    module Platform
      # THE OPERATOR'S READ DOOR onto the component status plane (design §6).
      #
      # Four reads and no writes. Every button the page renders comes out of a
      # row's `actions` array carrying its OWN permission and its own door;
      # `platform.status.read` buys the picture, never the actuation.
      #
      # Query logic lives in ::Platform::Status::Query and rollup arithmetic in
      # ::Platform::Status::Rollup, so the MCP tool answers the same questions
      # with the same code.
      class ComponentStatusesController < ApplicationController
        include Paginatable

        before_action :validate_permissions
        before_action :set_component, only: %i[show impact]

        # GET /api/v1/platform/component_statuses
        def index
          query = build_query
          return render_error("Unknown verdict filter: #{query.verdict}", status: :bad_request) unless query.known_verdict?

          # `.includes(:environment)` is READ, not decorative: the serializer
          # emits environment_slug/environment_name off the association (A4b).
          # Without it a 100-row page issues 100 plane lookups.
          rows = paginate(query.rows.includes(:environment))

          render_success(
            component_statuses: ::Platform::ComponentStatusSerializer.summary_collection(rows),
            filters: query.applied_filters,
            # An empty page under a plane nobody has is not the same answer as
            # an empty plane. Say which happened rather than making the client
            # guess from a zero.
            unknown_environment: query.unknown_environment?,
            meta: { pagination: pagination_meta }
          )
        end

        # GET /api/v1/platform/component_statuses/:id
        def show
          # ONE query for the whole neighbourhood, reused by both the impact
          # summary and the dependency panel — the alternative is a
          # neighbourhood query per rendered component (A1 report §8).
          neighbourhood = neighbourhood_rows(@component)

          render_success(
            component_status: ::Platform::ComponentStatusSerializer.detail(@component),
            impact: serialize_impact(::Platform::Status::Rollup.impact(@component, rows: neighbourhood))
          )
        end

        # GET /api/v1/platform/component_statuses/rollup
        def rollup
          query = build_query
          return render_error("Unknown verdict filter: #{query.verdict}", status: :bad_request) unless query.known_verdict?

          # SHARED ROWS ARE SPLIT OUT, not summed in (design §4.4, ruling
          # 2026-09-10), through the one predicate every door uses. The rows
          # are kept here, not just the two verdicts, because by_kind needs
          # each half too.
          account_rows, shared_rows = ::Platform::Status::Rollup.partition_shared(query.rows.to_a)

          render_success(
            rollup: ::Platform::Status::Rollup.rollup(account_rows),
            shared: ::Platform::Status::Rollup.rollup(shared_rows),
            by_kind: rollup_by_kind(account_rows),
            shared_by_kind: rollup_by_kind(shared_rows),
            filters: query.applied_filters,
            unknown_environment: query.unknown_environment?,
            observed_at: Time.current.utc.iso8601
          )
        end

        # GET /api/v1/platform/component_statuses/:id/impact
        def impact
          neighbourhood = neighbourhood_rows(@component)
          candidates = ::Platform::Status::Rollup.root_cause_candidates(@component, rows: neighbourhood)

          render_success(
            component_status: ::Platform::ComponentStatusSerializer.summary(@component),
            impact: serialize_impact(::Platform::Status::Rollup.impact(@component, rows: neighbourhood)),
            root_cause_candidates: ::Platform::ComponentStatusSerializer.summary_collection(candidates),
            # NOT a proof of causation. The ranking is correlation over the
            # dependency graph (design §4.6) and the page says so beside it;
            # an unlabelled ranking gets read as an answer.
            heuristic: true,
            heuristic_basis: "upstream-most unhealthy components, ranked by unhealthy-dependent count then earliest transition"
          )
        end

        private

        def validate_permissions
          require_permission("platform.status.read")
        end

        def build_query
          ::Platform::Status::Query.new(
            account: current_user.account,
            kind: params[:kind],
            verdict: params[:verdict],
            environment: params[:environment]
          )
        end

        # Scoped the way every other read here is: this account's rows plus the
        # shared ones. A component id belonging to another tenant is a 404, not
        # a 403 — the caller learns nothing about what exists elsewhere.
        def set_component
          @component = ::Platform::ComponentStatus
                       .where(account_id: [ current_user.account.id, nil ])
                       .find_by(id: params[:id])
          render_error("Component status not found", status: :not_found) unless @component
        end

        # THE NEIGHBOURHOOD IS THE READER'S, NOT THE COMPONENT'S.
        #
        # Keying this on `component.account_id` looked right and was wrong for
        # SHARED rows: a shared component's account_id is nil, so
        # `[component.account_id, nil].uniq` collapsed to `[nil]` and the walk
        # saw only other shared rows. Every dependent living in a real account
        # was invisible, so a shared circuit breaker's impact was always
        # understated — silently, with no error and a plausible-looking count.
        #
        # The right set is the one this reader can legally see, which is
        # exactly what Platform::Status::Query scopes to: this account's rows
        # plus the shared ones. For an account-scoped component that is the
        # same set as before; for a shared one it is the set that actually
        # contains its dependents.
        def neighbourhood_rows(_component)
          ::Platform::ComponentStatus.where(account_id: [ current_user.account.id, nil ])
                                     .includes(:environment).to_a
        end

        def serialize_impact(result)
          {
            count: result[:count],
            worst_verdict: result[:worst_verdict],
            components: ::Platform::ComponentStatusSerializer.summary_collection(result[:components])
          }
        end

        # Per-kind rollups beside the account-wide one, so a header can say
        # WHICH family is unhealthy without a second request per kind.
        def rollup_by_kind(rows)
          rows.group_by(&:component_kind).transform_values { |group| ::Platform::Status::Rollup.rollup(group) }
        end
      end
    end
  end
end
