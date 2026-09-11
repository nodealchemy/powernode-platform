# frozen_string_literal: true

module Platform
  # ONE TENANCY RULE for every drawer endpoint hanging off a component
  # (design §6, increment A9).
  #
  # The drawer is several endpoints across more than one controller — runbook,
  # remediation route, events, investigations — and every one of them resolves
  # the same `:component_status_id` for the same reader. Written out per
  # controller, that rule is a thing to keep in step, and the failure mode when
  # it drifts is a controller that quietly answers about another tenant's
  # component. So it lives here once.
  #
  # THE SCOPE IS THE READER'S: this account's rows plus the SHARED
  # (NULL-account) ones. A shared row describes process-wide infrastructure
  # that belongs to no tenant, and omitting it would make the shared components
  # the plane deliberately models unreachable from the drawer that exists to
  # explain them.
  #
  # A component id belonging to another account is a 404, NOT a 403. The caller
  # learns nothing about what exists elsewhere — the same choice A4's
  # controller and the internal conclude door both make, and the reason all
  # three say so out loud rather than leaving it to be inferred from a status
  # code.
  module ComponentStatusScoped
    extend ActiveSupport::Concern

    private

    def set_component_status
      @component_status = ::Platform::ComponentStatus
                          .where(account_id: [ current_user.account.id, nil ])
                          .find_by(id: params[:component_status_id] || params[:id])

      render_error("Component status not found", status: :not_found) if @component_status.nil?
    end

    # "shared" | "account" for the component, taken from
    # `Platform::ComponentStatusSerializer` rather than written a second time
    # (A9 review S4). That serializer is the one place the plane decides the
    # label, and A4's REST and MCP surfaces already emit it from there. A drawer
    # response that computed its own would be a second definition of "shared"
    # that could disagree with the list the operator clicked through from.
    def component_scope
      ::Platform::ComponentStatusSerializer.summary(@component_status)[:scope]
    end

    # The signal kind the sweep ROUTED this component to, or nil when nothing
    # routed it. Read off the persisted remediation payload rather than
    # re-derived: `Platform::Status::RemediationState` is the single writer of
    # that column, and a second derivation here could disagree with the one the
    # page already rendered.
    def routed_signal_kind
      remediation = @component_status.remediation
      return nil unless remediation.is_a?(Hash)

      remediation["signal_kind"].presence
    end
  end
end
