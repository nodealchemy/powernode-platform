# frozen_string_literal: true

require "open3"
require "net/http"

module Ai
  module Deploy
    module Methods
      # Dev / bare-metal platform-self deploy: restart the powernode systemd units after the
      # code has been advanced + migrated (the unprivileged git ff + db:migrate happen before
      # this; see the Orchestrator + the live-migrations rule). PRODUCTION self-deploy does
      # NOT use this — prod runs in managed VMs / containers / k8s (the Docker / Kubernetes
      # methods). This bridge crosses to root via `sudo systemctl`, so it is deliberately
      # constrained:
      #   - OFF by default — available only when POWERNODE_DEPLOY_SUDO_BRIDGE=enabled, which
      #     an operator sets AFTER installing a sudoers fragment that whitelists exactly the
      #     restart commands below. The platform never installs that fragment itself.
      #   - HARDCODED unit allowlist — never builds a unit name from input.
      #   - dry-run by default (the Orchestrator passes dry_run unless explicitly opted in),
      #     so by default it only PRINTS the systemctl commands it would run.
      class SudoBridge < Ai::Deploy::Method
        # The only units this bridge may restart. Hardcoded; defense-in-depth re-checked
        # at execution. Order: dependencies (worker/web) before backend, frontend last.
        UNIT_ALLOWLIST = %w[
          powernode-worker@default
          powernode-worker-web@default
          powernode-backend@default
          powernode-frontend@default
        ].freeze

        ENABLE_ENV = "POWERNODE_DEPLOY_SUDO_BRIDGE"
        HEALTH_URL = "http://localhost:3000/up"

        def self.key = :sudo_bridge

        # Gated OFF unless the operator opted in (after installing the sudoers fragment).
        def self.available? = ENV[ENABLE_ENV].to_s == "enabled"

        def self.supports?(target) = target.platform_self?

        def deploy!(target:, ref:, dry_run: true)
          return Ai::Deploy::Result.failure("sudo_bridge supports platform-self only") unless target.platform_self?

          commands = UNIT_ALLOWLIST.map { |unit| "sudo -n systemctl restart #{unit}" }
          if dry_run
            return Ai::Deploy::Result.dry(commands: commands, detail: "would restart #{UNIT_ALLOWLIST.size} units for #{ref}")
          end

          restarted = []
          UNIT_ALLOWLIST.each do |unit|
            unless restart_unit(unit)
              return Ai::Deploy::Result.failure("failed restarting #{unit}", restarted: restarted)
            end

            restarted << unit
          end
          Ai::Deploy::Result.ok("restarted #{restarted.join(', ')}", commands: commands, restarted: restarted)
        end

        def verify_health(target:, deploy_run:)
          code = http_status(HEALTH_URL)
          code == 200 ? Ai::Deploy::Result.ok("/up 200") : Ai::Deploy::Result.failure("/up returned #{code || 'no response'}")
        end

        def rollback!(target:, deploy_run:)
          # Best-effort: re-restart the units so the platform returns to a running state.
          # A true CODE rollback (git revert + re-migrate) is operator-gated — the
          # migration-safety gate up front is what keeps the forward deploy reversible.
          UNIT_ALLOWLIST.each { |unit| restart_unit(unit) }
          Ai::Deploy::Result.new(status: :rolled_back, detail: "units restarted; code rollback is operator-gated")
        end

        private

        def restart_unit(unit)
          return false unless UNIT_ALLOWLIST.include?(unit) # defense-in-depth: never restart off-list units

          _out, _err, status = Open3.capture3("sudo", "-n", "systemctl", "restart", unit)
          status.success?
        rescue StandardError => e
          Rails.logger.warn("[SudoBridge] restart #{unit} failed: #{e.message}")
          false
        end

        def http_status(url)
          uri = URI(url)
          Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 3) do |http|
            http.get(uri.path).code.to_i
          end
        rescue StandardError
          nil
        end
      end
    end
  end
end
