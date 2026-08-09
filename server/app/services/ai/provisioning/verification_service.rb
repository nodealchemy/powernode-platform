# frozen_string_literal: true

module Ai
  module Provisioning
    # Phase-4 verification for infrastructure missions (F2, IMP 019fe4c4-c7c4).
    #
    # Replaces the M2 stub that marked every mission healthy. Observed live
    # (dryrun 20260809a): the stub blessed — in 0.23s — a plan whose rna step
    # had recorded a provisioning failure and whose "running" instance was a
    # phantom the provider had never seen. Presence in the DB is never proof;
    # the protocol's infrastructure-truth oracle is live provider state.
    #
    # Checks, in three layers:
    #   1. PLAN   — the mission references a composed plan at all.
    #   2. STEPS  — every executed step is `completed`, recorded NO failures
    #      in `metadata.last_outputs.failures` (the executor records partial
    #      failures there and still returns success — see
    #      ProvisionFullStackExecutor), and produced exactly the instances it
    #      was asked for (inputs.count vs outputs.node_instance_ids).
    #   3. LIVE   — every produced instance is reconciled against the live
    #      provider through the `provision_verifier` extension seam: the row
    #      exists, carries provider identity, the provider reports it running,
    #      and it sits in the region the step declared. Core mode has no
    #      provider substrate; the absence is REPORTED in the checks rather
    #      than silently skipped, so a reader can tell "verified" from
    #      "unverifiable".
    #
    # Returns { healthy: Boolean, checks: [{ name:, ok:, detail: }, ...] }.
    # The caller (internal verify endpoint) fails the phase on unhealthy —
    # verification that cannot block is theater.
    class VerificationService
      def initialize(account:, mission:)
        @account = account
        @mission = mission
      end

      def verify
        plan = resolve_plan
        unless plan
          return result([ check("plan", false, "mission has no composed plan to verify") ])
        end

        checks = []
        expectations = []

        plan.steps.order(:step_number).each do |step|
          cfg = step.execution_config.is_a?(Hash) ? step.execution_config.deep_stringify_keys : {}
          next if cfg["skill"].blank?

          outs = last_outputs(step)
          prefix = "step_#{step.step_number}"

          checks << check("#{prefix}_status", step.status.to_s == "completed",
                          "status=#{step.status}")

          failures = Array(outs["failures"])
          checks << check("#{prefix}_failures", failures.empty?,
                          failures.empty? ? "no recorded failures" : "recorded failures: #{failures.inspect[0, 300]}")

          ids = Array(outs.dig("outputs", "node_instance_ids")).map(&:to_s)
          expected = cfg.dig("inputs", "count").to_i
          if expected.positive? || ids.any?
            checks << check("#{prefix}_count", ids.size == expected,
                            "provisioned #{ids.size}/#{expected} instances")
            region_id = cfg.dig("inputs", "provider_region_id")
            ids.each { |id| expectations << { node_instance_id: id, provider_region_id: region_id } }
          end
        end

        checks.concat(reconcile(expectations))
        result(checks)
      end

      private

      def resolve_plan
        plan_id = @mission&.configuration&.dig("plan", "plan_id")
        return nil if plan_id.blank?

        ::Ai::GoalPlan.find_by(id: plan_id)
      end

      def last_outputs(step)
        meta = step.metadata.is_a?(Hash) ? step.metadata : {}
        out = meta["last_outputs"] || meta[:last_outputs] || {}
        out.is_a?(Hash) ? out.deep_stringify_keys : {}
      end

      def reconcile(expectations)
        return [] if expectations.empty?

        reconciler = ::Powernode::ExtensionRegistry.provider(:provision_verifier)
        unless reconciler
          # Core mode: no provider substrate to ask. Healthy-but-annotated —
          # a reader must be able to tell "verified" from "unverifiable".
          return [ check("live_reconciliation", true,
                         "no provision_verifier registered (core mode) — " \
                         "#{expectations.size} instance(s) not live-verified") ]
        end

        Array(reconciler.reconcile_instances(account: @account, expectations: expectations)).map do |r|
          r = r.is_a?(Hash) ? r : {}
          check("instance_#{r[:node_instance_id] || r['node_instance_id']}",
                r[:ok].nil? ? r["ok"] == true : r[:ok] == true,
                (r[:detail] || r["detail"]).to_s)
        end
      rescue StandardError => e
        # A reconciler that cannot answer must not bless (fail-closed) — the
        # whole point is that silence and health are different things.
        [ check("live_reconciliation", false, "reconciler error: #{e.class}: #{e.message[0, 200]}") ]
      end

      def check(name, ok, detail)
        { name: name, ok: ok == true, detail: detail }
      end

      def result(checks)
        { healthy: checks.all? { |c| c[:ok] }, checks: checks }
      end
    end
  end
end
