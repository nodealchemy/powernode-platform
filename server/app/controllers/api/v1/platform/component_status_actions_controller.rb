# frozen_string_literal: true

module Api
  module V1
    module Platform
      # THE DRAWER'S READ ENDPOINTS (design §6, increment A9).
      #
      # A4's controller answers "what is the state of the plane". This answers
      # the three questions the drawer asks about ONE component once an
      # operator opens it:
      #
      #   GET :id/runbook            what should a person do about this
      #   GET :id/remediation_route  what would happen if they asked the platform to
      #   GET :id/events             what has already happened to it
      #
      # A SEPARATE controller from `ComponentStatusesController` deliberately:
      # that file is the plane's list-and-rollup surface and is owned
      # elsewhere, and bolting five drawer endpoints onto it would make one
      # controller answer two unrelated questions and cross the size line.
      #
      # ── ALL THREE ARE READS, AND `remediation_route` IS THE ONE TO WATCH ────
      # `Platform::RemediationRouter.route` consults the owning lane's
      # `describe`, which is a GATE CHECK, not an actuation: it reports what a
      # lane would say, and constructs no proceed. That is the whole reason the
      # drawer can show an operator the consequences before they choose. If a
      # lane ever starts mutating inside `describe`, this endpoint becomes a
      # write and this comment becomes wrong — which is why the contract is
      # stated here at the call site rather than assumed from the method name.
      #
      # ── THE LEADING :: IS LOAD-BEARING ──────────────────────────────────────
      # This class is lexically inside `Api::V1::Platform`, so a bare
      # `Platform::RemediationRouter` resolves to
      # `Api::V1::Platform::RemediationRouter` and raises NameError. Same trap
      # the internal controllers document.
      class ComponentStatusActionsController < ApplicationController
        include Paginatable
        include ::Platform::ComponentStatusScoped

        before_action :validate_permissions
        before_action :set_component_status

        # A component with no routed signal has no runbook and no route, and
        # that is a different answer from "we looked and found nothing
        # registered". Reported as its own reason so the drawer can say which.
        NO_ROUTED_SIGNAL = "NoRoutedSignal"

        # GET /api/v1/platform/component_statuses/:component_status_id/runbook
        def runbook
          kind = routed_signal_kind

          render_success(
            component_status_id: @component_status.id,
            signal_kind: kind,
            runbook: kind.nil? ? no_signal_runbook : ::Platform::Runbook::Registry.render(kind)
          )
        end

        # GET /api/v1/platform/component_statuses/:component_status_id/remediation_route
        def remediation_route
          kind = routed_signal_kind

          if kind.nil?
            return render_success(component_status_id: @component_status.id, signal_kind: nil,
                                  routed: false, reason: NO_ROUTED_SIGNAL,
                                  runbook: no_signal_runbook)
          end

          route = ::Platform::RemediationRouter.route(@component_status, signal_kind: kind)

          render_success(
            component_status_id: @component_status.id,
            signal_kind: kind,
            routed: true,
            route: serialize_route(route)
          )
        end

        # GET /api/v1/platform/component_statuses/:component_status_id/events
        #
        # Keyed on (component_kind, component_ref), NOT on component_status_id:
        # a component that is reaped and re-created gets a new row id but is the
        # same thing to an operator, and its history must survive that. The
        # composite index on (component_kind, component_ref, occurred_at) is
        # exactly this query.
        def events
          rows = ::Platform::StatusEvent
                 .for_component(@component_status.component_kind, @component_status.component_ref)
                 .recent_first

          events = paginate(rows)

          render_success(
            component_status_id: @component_status.id,
            events: events.map { |event| serialize_event(event) },
            meta: { pagination: pagination_meta }
          )
        end

        private

        def validate_permissions
          require_permission("platform.status.read")
        end

        # DISTINCT from the registry's own `NotRegistered`. "Nothing routed
        # this component" and "something routed it and no runbook is
        # registered for that kind" are different situations with different
        # fixes, and collapsing them sends an operator to look for a missing
        # document that was never supposed to exist.
        def no_signal_runbook
          { kind: "none", known: false, reason: NO_ROUTED_SIGNAL }
        end

        # The router's own keys, passed through rather than renamed. A drawer
        # field named differently from the thing that produced it is a mapping
        # somebody has to maintain in two places.
        def serialize_route(route)
          {
            state: route[:state],
            lane_key: route[:lane_key],
            policy: route[:policy],
            consent: route[:consent],
            disruption: route[:disruption],
            environment_ceiling: route[:environment_ceiling],
            blast_radius: route[:blast_radius],
            can_proceed: route[:can_proceed],
            reason: route[:reason],
            lane_reason: route[:lane_reason],
            runbook: route[:runbook]
          }
        end

        def serialize_event(event)
          {
            id: event.id,
            kind: event.kind,
            from_verdict: event.from_verdict,
            to_verdict: event.to_verdict,
            occurred_at: event.occurred_at&.utc&.iso8601,
            payload: event.payload || {}
          }
        end
      end
    end
  end
end
