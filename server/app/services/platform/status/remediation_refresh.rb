# frozen_string_literal: true

module Platform
  module Status
    # RE-DERIVES the remediation state of every component in an account, after
    # the sweep has refreshed their verdicts.
    #
    # ── THE CALL SITE (for the A2 runner) ───────────────────────────────────
    # A2's worker route owns the sweep. It should call this immediately after
    # Platform::Status::SweepService#run_once!, inside the same guarded block,
    # and merge the result into what it reports:
    #
    #   sweep = ::Platform::Status::SweepService.new.run_once!(account)
    #   remediation = ::Platform::Status::RemediationRefresh.run!(account)
    #
    # AFTER the sweep, not before: the sweep is what creates rows for
    # newly-appeared components, and refreshing first would leave every new
    # row with no remediation state until the next tick. It is a separate call
    # rather than a hook inside the sweep because the two have different
    # failure modes — a signal source that is down must not stop verdicts from
    # being written — and because A1 deliberately made `run_once!` the
    # guard-free unit that its oracle runs without Redis or a worker.
    #
    # ── EMPTY IS A SKIP, NOT A SWEEP OF `none` ──────────────────────────────
    # With no signal source registered, every component would derive `none` —
    # which is indistinguishable from "we looked and nothing is signalling",
    # and would silently overwrite whatever a source wrote before it was
    # unregistered. So a run with no sources registered writes NOTHING and
    # says so. A refresh that cannot see is not a refresh that saw nothing.
    module RemediationRefresh
      NO_SOURCES = "NoSignalSources"

      class << self
        # @param account [Account, String] the account, or its id
        # @return [Hash] account_id:, refreshed:, skipped:, reason:, states:, errors:
        def run!(account)
          account_id = account.is_a?(::Account) ? account.id : account

          unless ::Platform::Status::SignalSources.any?
            return { account_id: account_id, refreshed: 0, skipped: true, reason: NO_SOURCES,
                     states: {}, errors: [] }
          end

          states = Hash.new(0)
          errors = []
          refreshed = 0

          # Eager-loaded: the router asks each row for its account, and a page
          # of components would otherwise issue one query per row.
          scope_for(account_id).find_each do |component_status|
            payload = ::Platform::Status::RemediationState.derive(
              component_status,
              signals: ::Platform::Status::SignalSources.signals_for(component_status)
            )
            states[payload["state"]] += 1
            refreshed += 1
          rescue StandardError => e
            # One unwritable row must not abandon the rest of the account.
            # Reported in the result AND logged, so a partial refresh is
            # visible as a partial refresh rather than as a smaller fleet.
            Rails.logger.error(
              "[Platform::Status::RemediationRefresh] #{component_status.component_kind}/" \
              "#{component_status.component_ref}: #{e.class}: #{e.message}"
            )
            errors << { component_kind: component_status.component_kind,
                        component_ref: component_status.component_ref,
                        error: "#{e.class}: #{e.message}" }
          end

          { account_id: account_id, refreshed: refreshed, skipped: false, reason: nil,
            states: states.to_h, errors: errors }
        end

        private

        # The same scope A1's reap arm uses: this account's rows plus the
        # shared (null-account) rows. A global scope would re-derive another
        # tenant's components purely because this one was swept.
        def scope_for(account_id)
          ::Platform::ComponentStatus
            .where(account_id: [ account_id, nil ])
            .includes(:account)
        end
      end
    end
  end
end
