# frozen_string_literal: true

module Ai
  module Deploy
    # Base class for a deploy method (mechanism/strategy): Workload (managed project),
    # Docker (container/swarm rollout), Kubernetes (rollout via the cluster), SudoBridge
    # (dev/bare-metal platform-self via systemctl). The Orchestrator owns the shared
    # safety envelope (kill-switch, migration-safety, health gate, auto-rollback, audit);
    # a Method only performs the deploy mechanism and reports a Result.
    #
    # Contract:
    #   - deploy!(target:, ref:, dry_run:) — when dry_run is true the method MUST NOT
    #     mutate anything and returns Result.dry(commands: [...]) listing what it would do.
    #   - rollback!(target:, deploy_run:) — best-effort revert for auto-rollback.
    class Method
      # Unique registry key (Symbol), e.g. :workload, :docker, :kubernetes, :sudo_bridge.
      def self.key
        raise NotImplementedError, "#{name} must define .key"
      end

      # Whether this method can run in this install (deps/flags/extension present).
      def self.available?
        true
      end

      # Whether this method can handle the given target.
      def self.supports?(_target)
        true
      end

      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      def key
        self.class.key
      end

      # Perform (or, when dry_run, describe) the deploy. Return an Ai::Deploy::Result.
      def deploy!(target:, ref:, dry_run: true)
        raise NotImplementedError, "#{self.class.name} must implement #deploy!"
      end

      # Post-deploy health verification used by the Orchestrator to decide whether to
      # auto-rollback. Default: assume healthy (methods that can check — SudoBridge /up,
      # Workload via DeploymentGuardian — override). Return Result.ok when healthy,
      # Result.failure(reason) when not.
      def verify_health(target:, deploy_run:)
        Ai::Deploy::Result.ok("no health check for #{key}")
      end

      # Best-effort rollback of a prior deploy. Default: not supported.
      def rollback!(target:, deploy_run:)
        Ai::Deploy::Result.failure("rollback not implemented for #{key}")
      end

      private

      attr_reader :account, :user
    end
  end
end
